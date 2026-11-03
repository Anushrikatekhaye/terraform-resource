# -----------------------------------------------------------------------------
# terraform.tfvars - Values for this deployment.
# Contains NO secrets (no keys, passwords or account IDs), so it is safe to commit.
# -----------------------------------------------------------------------------

aws_region   = "ap-south-1"
project_name = "nlb-asg"
environment  = "dev"
owner        = "devops-team"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
single_nat_gateway   = true # set to false for one NAT Gateway per AZ (HA, ~2x NAT cost)

# Security
allowed_http_cidrs  = ["0.0.0.0/0"]
ssh_allowed_cidrs   = [] # empty = SSH only from inside the VPC; use SSM Session Manager
ssh_public_key_path = "~/.ssh/aws-nlb-demo.pub"

# Compute
instance_type              = "t3.micro"
root_volume_size           = 8
cpu_credits                = "unlimited"
enable_detailed_monitoring = true

# Load balancer
app_port                   = 80
enable_deletion_protection = false

# Auto Scaling
asg_min_size              = 2
asg_desired_capacity      = 2
asg_max_size              = 4
health_check_grace_period = 300
target_cpu_utilization    = 60
instance_warmup           = 120
