# Every resource explained

| File | Resource | What it does | Why it is configured this way |
|------|----------|--------------|-------------------------------|
| `provider.tf` | `terraform` block, `backend "s3"` | Pins Terraform and provider versions, stores state in S3 | `use_lockfile = true` locks the state with an S3 object (no DynamoDB). Bucket and region are passed at init so nothing account-specific is committed. |
| `provider.tf` | `provider "aws"` + `default_tags` | Region and tags applied to all taggable resources | Consistent tagging without repeating it on every resource. |
| `main.tf` | `data.aws_availability_zones` | Lists usable AZs | The first two are used, so the code works in any region. |
| `main.tf` | `data.aws_ami.ubuntu` | Finds the latest Ubuntu 24.04 LTS AMI from Canonical (owner `099720109477`) | No hardcoded AMI ID. Set `ami_id` to pin a version and avoid surprise instance refreshes. |
| `main.tf` | `aws_iam_role`, `aws_iam_role_policy_attachment`, `aws_iam_instance_profile` | Identity for the instances with only `AmazonSSMManagedInstanceCore` | Gives shell access via Session Manager without exposing SSH. No other permissions (least privilege). |
| `main.tf` | `aws_key_pair` | Uploads your **public** SSH key | The private key stays on your machine. |
| `vpc.tf` | `aws_vpc` | Private network `10.0.0.0/16` with DNS support and DNS hostnames enabled | DNS hostnames give instances names like `ip-10-0-11-25.ap-south-1.compute.internal`. |
| `vpc.tf` | `aws_internet_gateway` | Connects the VPC to the internet | Required for the internet-facing NLB and for NAT Gateways. |
| `vpc.tf` | `aws_subnet.public` (x2, `for_each`) | One public subnet per AZ for the NLB nodes and NAT Gateway | `map_public_ip_on_launch = false`: nothing launched here needs a public IP. |
| `vpc.tf` | `aws_subnet.private` (x2, `for_each`) | One private subnet per AZ for the web servers | Instances are unreachable directly from the internet. |
| `vpc.tf` | `aws_eip.nat`, `aws_nat_gateway.main` | Outbound-only internet access for private instances (apt, SSM) | `single_nat_gateway` chooses one shared NAT (cheap) or one per AZ (HA). |
| `vpc.tf` | `aws_route_table.public` + `aws_route.public_internet` + associations | Sends `0.0.0.0/0` from public subnets to the IGW | This is what makes a subnet "public". |
| `vpc.tf` | `aws_route_table.private` (per AZ) + `aws_route.private_nat` + associations | Sends `0.0.0.0/0` from private subnets to a NAT Gateway | One route table per AZ so each AZ can use its own NAT in HA mode. |
| `security_groups.tf` | `aws_security_group.nlb` + ingress/egress rules | Allows port 80 from `allowed_http_cidrs`; egress only to the EC2 security group | The NLB can talk to nothing else. |
| `security_groups.tf` | `aws_security_group.ec2` + rules | Port 80 **only from the NLB security group**, SSH only from trusted CIDRs (default: inside the VPC), outbound only 80/443 | Separate groups per tier, referencing groups instead of CIDRs. `create_before_destroy` + `name_prefix` allow safe replacement. |
| `launch_template.tf` | `aws_launch_template.web` | The blueprint for instances: AMI, `t3.micro`, key pair, SG, instance profile, user data, EBS, tags | IMDSv2 required, encrypted gp3 root volume, detailed monitoring, `update_default_version`. `tag_specifications` propagate tags to instances and volumes. |
| `userdata.sh` | (script) | Installs Nginx and `stress-ng`, writes a welcome page with hostname, instance ID, AZ and IP, hides the Nginx version | Runs at every first boot, so every instance the ASG launches configures itself with no manual steps. Log: `/var/log/user-data.log`. |
| `nlb.tf` | `aws_lb.nlb` | Internet-facing Network Load Balancer in both public subnets | Cross-zone load balancing enabled; has its own security group. |
| `nlb.tf` | `aws_lb_target_group.web` | TCP :80 target group, `target_type = instance`, HTTP health check on `/` using the traffic port | Interval 10 s, threshold 3/3 → a failing instance is out of rotation in about 30 s. `preserve_client_ip = false` allows SG-to-SG rules. |
| `nlb.tf` | `aws_lb_listener.tcp` | Listens on TCP :80 and forwards to the target group | The entry point of the load balancer. |
| `autoscaling.tf` | `aws_autoscaling_group.web` | Keeps 2-4 instances running in the private subnets and registers them with the target group | ELB health checks, 300 s grace period, balanced AZ distribution, termination policies, rolling instance refresh, tags propagated to instances. |
| `autoscaling.tf` | `aws_autoscaling_policy.cpu_target_tracking` | Target tracking on `ASGAverageCPUUtilization` = 60% | AWS creates and manages the CloudWatch alarms; handles both scale-out and scale-in. |
| `outputs.tf` | `output` blocks | NLB DNS name and URL, IDs, ready-to-run AWS CLI commands | Makes testing copy-paste easy. |
| `scripts/bootstrap-state.sh` | (script) | Creates the S3 bucket with versioning, encryption and public access blocked, writes `backend.hcl` | Solves the "chicken and egg" problem of needing a bucket before Terraform can store state. |
