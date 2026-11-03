# Key concepts

## Network Load Balancer vs Application Load Balancer

| | Network Load Balancer (NLB) | Application Load Balancer (ALB) |
|---|---|---|
| OSI layer | Layer 4 (TCP, UDP, TLS) | Layer 7 (HTTP, HTTPS, gRPC, WebSocket) |
| Routing | By IP protocol and port (flow hash) | By host, path, header, query string, method |
| Performance | Millions of requests/s, ultra-low latency, handles sudden spikes | Very good, but adds L7 processing |
| Static IPs | One per AZ, Elastic IPs supported | No static IPs (use Global Accelerator) |
| Security groups | Optional (attached at creation) | Yes |
| Extras | PrivateLink, preserves client IP, non-HTTP protocols | WAF, authentication (OIDC/Cognito), redirects, fixed responses |

**Use an NLB** for non-HTTP protocols, extreme throughput/low latency, static IPs, or PrivateLink. **Use an ALB** for web apps and microservices that need smart HTTP routing or WAF. This project uses an NLB because the task is a Layer 4 TCP design.

## Auto Scaling Group vs Launch Template

- **Launch Template**: the *what*. A versioned blueprint for one instance (AMI, type, key pair, security groups, user data, IAM profile, tags). It launches nothing by itself.
- **Auto Scaling Group**: the *how many and where*. It uses a launch template to keep the right number of instances alive across subnets/AZs, replaces unhealthy ones, registers them with load balancers and scales them with policies.

## NLB listener and target group

- **Listener**: the front door. It checks for connection requests on a protocol and port (here TCP 80) and decides what to do (here: forward).
- **Target group**: the back end. A set of targets (EC2 instances) plus the health-check settings. The listener forwards to the target group; the ASG registers instances into it.

## TCP vs HTTP health checks

- **TCP**: succeeds if the target accepts a TCP connection. Fast and protocol-agnostic, but a hung or broken application whose port is still open looks "healthy".
- **HTTP**: sends a real request (`GET /`) and requires a 2xx/3xx response. It proves the application is serving content. This project uses HTTP health checks even though the listener is TCP, which NLB supports.

## Minimum, desired and maximum capacity

- **Minimum (2)**: the ASG never goes below it, even if CPU is 0%.
- **Desired (2)**: the number the ASG is trying to maintain right now. Scaling policies change it.
- **Maximum (4)**: the hard ceiling, which protects your budget.

## Target tracking scaling policy

You pick a metric and a target (average CPU = 60%). The ASG behaves like a thermostat: it computes how much capacity is needed to bring the metric back to the target, adds or removes instances accordingly, and creates the CloudWatch alarms itself. Compared with step scaling you do not hand-write alarms and step adjustments. Scale-out is aggressive, scale-in is conservative (15 minutes of low data), to avoid flapping.

## EC2 health checks vs ELB health checks

- **EC2 (default)**: only checks the instance state and system status checks. If Nginx crashes but the VM is running, the instance is still "healthy".
- **ELB**: also uses the load balancer's target health. If the target group marks the instance unhealthy, the ASG terminates and replaces it. This project sets `health_check_type = "ELB"` with a 300 s **grace period** so new instances have time to install Nginx before being judged.

## Cross-zone load balancing

Without it each NLB node only sends traffic to targets in its own AZ, so uneven instance counts per AZ cause uneven load. With it enabled each node distributes across all healthy targets in all AZs, so load is even. Trade-off: NLB cross-zone traffic is charged as inter-AZ data transfer (ALB does not charge for it).

## High availability across Availability Zones

Each AZ is an isolated data center group. This design spreads the NLB nodes (public subnets), the instances (private subnets) and, optionally, the NAT Gateways across two AZs. If one AZ fails, the NLB stops routing to its targets and the ASG launches replacements in the surviving AZ. The one single point of failure by default is the shared NAT Gateway: it affects only outbound access (installing packages), not serving traffic. Set `single_nat_gateway = false` to remove it.

## Dynamic scaling and horizontal scaling

- **Horizontal scaling (scale out/in)**: change the *number* of instances. Cheap, no downtime, and the basis of ASGs.
- **Vertical scaling (scale up/down)**: change the *size* of an instance (t3.micro → t3.large). Needs a restart and has a ceiling.
- **Dynamic scaling**: reacts to live metrics (target tracking, step, simple scaling). Other kinds are **scheduled** (known traffic patterns) and **predictive** (ML-based forecasts).

## How CloudWatch monitors CPU and how the ASG responds

1. Each instance sends `CPUUtilization` to CloudWatch every 1 minute (detailed monitoring).
2. CloudWatch aggregates those into the ASG-level metric `ASGAverageCPUUtilization`.
3. The target tracking policy owns two alarms (`TargetTracking-<asg>-AlarmHigh-…` and `…-AlarmLow-…`).
4. When AlarmHigh fires (3 consecutive 1-minute datapoints above 60%), the ASG launches the number of instances needed, limited by `max_size`. New instances wait out the warmup period before their CPU counts.
5. When AlarmLow fires (15 consecutive datapoints well below target), the ASG terminates instances using the termination policies, never below `min_size`.
6. Instances in the target group are drained (60 s deregistration delay) before termination, so connections finish.
