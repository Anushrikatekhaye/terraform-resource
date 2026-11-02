# AWS Network Load Balancer with Terraform

A hands-on DevOps project: an internet-facing **Network Load Balancer (NLB)** distributing TCP traffic across two Ubuntu EC2 instances running Nginx, in two Availability Zones, all built with Terraform.

## Traffic flow

1. User sends an HTTP request.
2. Request reaches the AWS Network Load Balancer DNS name.
3. The NLB listener receives traffic on TCP port 80.
4. The NLB forwards traffic to the target group.
5. The target group distributes traffic across two EC2 instances.
6. Nginx responds with that instance's welcome page.

## Architecture

```
                               Internet
                                  |
                          [ Internet Gateway ]
                                  |
   VPC 10.0.0.0/16                |
  +-------------------------------+----------------------------------+
  |                               |                                  |
  |        Network Load Balancer (TCP :80, cross-zone enabled)       |
  |        security group: nlb-sg  (80 from allowed CIDRs)           |
  |             |                                  |                 |
  |   +---------+---------+            +-----------+-------+         |
  |   | Public subnet A   |            | Public subnet B   |         |
  |   | 10.0.1.0/24 (AZ a)|            | 10.0.2.0/24 (AZ b)|         |
  |   | NLB node          |            | NLB node          |         |
  |   | EC2 web-1 (Nginx) |            | EC2 web-2 (Nginx) |         |
  |   | instances-sg      |            | instances-sg      |         |
  |   +-------------------+            +-------------------+         |
  |                                                                  |
  |   Private subnet A 10.0.11.0/24    Private subnet B 10.0.12.0/24 |
  |   (reserved for future back-end tiers, local routes only)        |
  +------------------------------------------------------------------+

  Target group: TCP :80, health check HTTP GET / on :80
  Public route table: 0.0.0.0/0 -> Internet Gateway
```

## Folder structure

```
nlb-terraform/
├── provider.tf          # Terraform + provider versions, S3 backend, default tags
├── variables.tf         # All input variables with descriptions and validation
├── main.tf              # Shared data sources (AZs, Ubuntu AMI), locals, input checks
├── vpc.tf               # VPC, subnets, IGW, route tables, associations
├── security_groups.tf   # NLB SG and instance SG (least privilege)
├── ec2.tf               # IAM for SSM, two Ubuntu instances, Nginx user data
├── nlb.tf               # NLB, target group, attachments, TCP listener
├── outputs.tf           # DNS name, URL, IDs, health-check command
├── terraform.tfvars     # Values for this deployment
├── .gitignore
└── README.md
```

## What each resource does

| Resource | File | Purpose |
|---|---|---|
| `aws_vpc.main` | vpc.tf | Isolated network, CIDR `10.0.0.0/16`, DNS support on |
| `aws_default_security_group` | vpc.tf | Strips all rules from the default SG so nothing uses it by accident |
| `aws_internet_gateway.main` | vpc.tf | Gives the public subnets a path to and from the internet |
| `aws_subnet.public` (x2) | vpc.tf | One per AZ; hold the NLB nodes and the Nginx instances |
| `aws_subnet.private` (x2) | vpc.tf | One per AZ; reserved for future internal tiers (local routes only) |
| `aws_route_table.public` + `aws_route` | vpc.tf | Sends `0.0.0.0/0` to the internet gateway |
| `aws_route_table_association` | vpc.tf | Attaches the route tables to the subnets |
| `aws_security_group.nlb` | security_groups.tf | Controls who can reach the listener; may only send to instances on port 80 |
| `aws_security_group.instances` | security_groups.tf | Accepts port 80 only from the NLB security group |
| `aws_iam_role` + instance profile | ec2.tf | SSM Session Manager access, so no SSH key and no port 22 |
| `aws_instance.web` (x2, `for_each`) | ec2.tf | Ubuntu 24.04 + Nginx via user data, a different welcome page on each |
| `aws_lb.nlb` | nlb.tf | The Network Load Balancer, one node per AZ, cross-zone on |
| `aws_lb_target_group.nginx` | nlb.tf | TCP :80 target group with an HTTP `/` health check |
| `aws_lb_target_group_attachment` | nlb.tf | Registers each instance as a target |
| `aws_lb_listener.tcp` | nlb.tf | TCP :80 listener that forwards to the target group |

## Prerequisites

- Terraform 1.10 or newer (needed for S3 native locking via `use_lockfile`)
- AWS CLI configured (`aws configure`) with permissions for VPC, EC2, ELB, IAM and S3
- An S3 bucket for remote state (next section)

## Remote state (S3 backend with lockfile)

The backend block lives in `provider.tf`. Backend blocks cannot use variables, so the bucket name is supplied at init time. `use_lockfile = true` makes Terraform create a `.tflock` object next to the state file, which prevents two people applying at once. No DynamoDB table is needed.

Create the bucket once (names are global, so choose your own):

```bash
BUCKET=my-tfstate-$(aws sts get-caller-identity --query Account --output text)-ap-south-1

aws s3api create-bucket --bucket "$BUCKET" --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

## Deployment workflow

```bash
terraform init -backend-config="bucket=$BUCKET"
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
terraform destroy
```

| Command | What it does | Common errors and fixes |
|---|---|---|
| `terraform init` | Downloads the AWS provider and connects the S3 backend | `bucket: required` -> pass `-backend-config="bucket=..."`. `AccessDenied` / `NoSuchBucket` -> check the bucket name, region and your credentials. After changing backend settings use `terraform init -reconfigure`. |
| `terraform fmt` | Rewrites files to the canonical style | Nothing fails; run it before every commit. `-check` is useful in CI. |
| `terraform validate` | Checks syntax and references without touching AWS | `Reference to undeclared resource` -> typo in a resource name. `Unsupported argument` -> wrong provider version or attribute name. |
| `terraform plan` | Shows what will be created, changed or destroyed | `No valid credential sources` -> run `aws configure` or export credentials. `Error acquiring the state lock` -> another run is active, or a crashed run left a lock; wait, or `terraform force-unlock <ID>` once you are sure nobody is running. |
| `terraform apply` | Creates the real resources (about 3 to 5 minutes) | `UnauthorizedOperation` -> missing IAM permission. `InvalidParameterValue` on the target group -> read the message; NLB needs equal healthy/unhealthy thresholds. `VpcLimitExceeded` -> delete unused VPCs. |
| `terraform output` | Prints the values from `outputs.tf` | Empty output means apply has not finished or failed. Use `terraform output -raw nlb_dns_name` in scripts. |
| `terraform destroy` | Deletes everything Terraform created | `DependencyViolation` -> something outside Terraform uses the resource (for example a manually attached ENI). Remove it and retry. |

## Testing and validation

Wait 2 to 3 minutes after apply: instances need time to run apt and install Nginx, then the target group needs three passing health checks.

```bash
# 1. Get the URL and open it in a browser
terraform output nlb_url

# 2. Check from the terminal. Repeat it and watch the page title change
for i in $(seq 1 10); do curl -s "$(terraform output -raw nlb_url)" | grep -o "Welcome to web-[0-9]"; done

# 3. Target health (the console equivalent is EC2 > Target Groups > Targets tab)
$(terraform output -raw check_target_health_command)
```

Both targets should show `healthy`.

**About traffic distribution:** an NLB balances by connection, using a flow hash of the connection details, not per request. A browser reuses one connection (keep-alive), so refreshing may keep hitting the same instance. Use the `curl` loop above (each call opens a new connection with a new source port), a private/incognito window, or `curl --no-keepalive`. Seeing both pages appear is the proof of distribution.

### Failure test: make one instance unhealthy

```bash
# Open a shell on web-1 through SSM (no SSH needed)
aws ssm start-session --target "$(terraform output -json instance_ids | jq -r '."web-1"')" --region ap-south-1

# Inside the instance, stop Nginx
sudo systemctl stop nginx
```

After about 30 seconds (3 failed checks at a 10 second interval) web-1 turns `unhealthy`. Re-run the `curl` loop: every response now comes from web-2 and users see no errors. Start Nginx again (`sudo systemctl start nginx`) and web-1 returns to `healthy` after 3 passing checks. This is the high availability behaviour of the target group.

## Troubleshooting unhealthy targets

| Symptom | Likely cause | How to check and fix |
|---|---|---|
| Target `unhealthy`, reason `Target.FailedHealthChecks` | Nginx not running or user data failed | SSM into the instance: `systemctl status nginx`, `sudo cat /var/log/cloud-init-output.log` |
| Target stuck in `initial` | Still booting, or fewer than 3 passing checks | Wait a few minutes; check `cloud-init status` on the instance |
| Health check times out | Instance security group blocks the NLB | Confirm `instances_from_nlb` allows port 80 from the NLB security group |
| Health check returns non-2xx/3xx | Wrong path or Nginx returns 404/403 | `curl -i localhost/` on the instance; match `health_check_path` and `matcher` |
| NLB DNS works but the page never loads | Listener port, client CIDR or NLB security group | Check `allowed_client_cidrs` and the listener port in `terraform.tfvars` |
| NLB DNS name does not resolve yet | NLB still provisioning | Wait until the state is `active`: `aws elbv2 describe-load-balancers` |
| Nginx never installed | No outbound internet from the instance | Instances need a public IP, the public route table and the HTTP/HTTPS egress rules |
| Nothing in the target group | Attachment missing | `aws elbv2 describe-target-health` and check `aws_lb_target_group_attachment` in the plan |

## Why a Network Load Balancer instead of an Application Load Balancer?

| | Network Load Balancer | Application Load Balancer |
|---|---|---|
| OSI layer | Layer 4 (TCP, UDP, TLS) | Layer 7 (HTTP, HTTPS, gRPC) |
| Routing | By connection and port | By host, path, header, query string |
| Performance | Millions of requests per second, ultra-low latency | Higher latency (inspects each request) |
| IP addresses | One static IP per AZ, Elastic IP supported | Changing IPs, only a DNS name |
| Best for | TCP/UDP services, non-HTTP protocols, very high throughput, static IPs, PrivateLink | Websites and APIs needing path/host routing, redirects, WAF, auth |

Choose an NLB when you need raw speed, static IPs for allow-listing, non-HTTP protocols or PrivateLink. Choose an ALB when you need HTTP-aware routing. Here the NLB is used to learn Layer 4 balancing and its health check behaviour.

## Concepts explained

**Listener.** A process on the NLB that checks for connection requests on a protocol and port (TCP 80 here) and applies a rule: forward to the target group.

**Target group.** The set of back ends that receive traffic. It defines the protocol and port used to reach targets and how they are health checked. Targets are registered with attachments.

**TCP vs HTTP health checks.** A TCP check only confirms the port accepts a connection, so a hung or broken Nginx that still has the port open passes. An HTTP check requests `/` and expects a 200 to 399 response, so it proves the application actually works. This project keeps the traffic protocol TCP but uses an HTTP health check, which is allowed on NLB target groups. The trade-off is slightly more load on the targets.

**Availability Zones and high availability.** Each AZ is a separate data center group. The NLB has a node in each public subnet, and each instance is in a different AZ. If one AZ or one instance fails, the health check removes it and traffic continues to the other.

**Cross-zone load balancing.** Off (the NLB default): each NLB node sends traffic only to targets in its own AZ, so uneven target counts get uneven load. On (this project): every node can send to targets in all AZs, giving an even spread and better resilience. The cost is cross-AZ data transfer charges for the NLB.

**Client IP preservation.** For instance targets the NLB can pass the real client IP to the instance. This project turns it off so traffic arrives from the NLB and the instance security group can reference the NLB security group instead of opening port 80 to the internet. The trade-off: Nginx logs show NLB addresses, not client IPs (Proxy Protocol v2 can restore them).

## Security best practices applied

- **Least privilege security groups:** the internet reaches only the NLB; instances accept port 80 only from the NLB security group; the NLB can only send to instances on port 80
- **No SSH:** shell access uses SSM Session Manager, so there is no key pair and no port 22 open
- **IMDSv2 required** on the instances, and the **default security group has no rules**
- **Encrypted EBS** root volumes, and encrypted, versioned, private S3 state bucket
- **State locking** with S3 lockfiles to prevent concurrent applies
- **Tags** on everything through provider `default_tags`, consistent naming `<project>-<env>-<name>`
- **Input validation** on `environment`, plus `check` blocks for mismatched subnet counts
- **Deletion protection** variable for production
- No secrets in code or `terraform.tfvars`

For production, add: NLB TLS listener with an ACM certificate, instances in private subnets behind a NAT gateway or VPC endpoints, an Auto Scaling group instead of fixed instances, CloudWatch alarms on `UnHealthyHostCount`, and a CI pipeline running `terraform fmt -check`, `validate`, `tflint` and `checkov`.

## Cost note

The NLB bills hourly plus per Load Balancer Capacity Unit, and the two `t3.micro` instances bill hourly. Run `terraform destroy` when you finish practicing.

## Interview questions and answers

**1. Why did you use an NLB here, and when would you pick an ALB instead?**
An NLB works at Layer 4, so it forwards TCP connections with very low latency, gives a static IP per AZ and handles non-HTTP protocols. I would pick an ALB when I need Layer 7 features such as path or host-based routing, redirects, WAF integration or authentication.

**2. What is the difference between TCP and HTTP health checks, and which did you configure?**
A TCP check only verifies the port accepts a connection. An HTTP check requests a path and validates the status code, so it proves the application works. I used a TCP target group with an HTTP health check on `/` port 80, so a running but broken Nginx is detected and removed.

**3. What does cross-zone load balancing do, and what is the trade-off?**
It lets every NLB node send traffic to targets in all AZs, so load is even regardless of how many targets each AZ has, and losing targets in one AZ is absorbed. The trade-off is cross-AZ data transfer cost and slightly more latency; with it off, each node only serves targets in its own AZ.

**4. One instance fails. What happens, and how did you test it?**
The health check fails three times in a row (about 30 seconds), the target is marked unhealthy and the NLB stops sending new connections to it. Existing connections to it may fail. Traffic continues to the healthy instance in the other AZ. I tested it by stopping Nginx on web-1 through SSM and running a curl loop that returned only web-2, then restarted Nginx and watched web-1 return to healthy.

**4a. Follow-up: how do you troubleshoot an unhealthy target?**
Check the target health reason, then SSM into the instance and look at `systemctl status nginx` and cloud-init logs, test `curl localhost/`, and confirm the instance security group allows the NLB security group on the health check port.

**5. How do you manage Terraform state safely in a team?**
Store state in a versioned, encrypted, private S3 bucket and enable locking. With Terraform 1.10 and later the S3 backend supports native lockfiles (`use_lockfile = true`), so no DynamoDB table is needed. Locking stops two applies from corrupting the state, and versioning lets me recover an older state.
