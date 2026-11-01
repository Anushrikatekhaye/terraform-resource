# Values for this deployment. No secrets here (only the PUBLIC key path), so it is safe to commit.
aws_region  = "ap-south-1"
project     = "asg-demo"
environment = "dev"
owner       = "devops"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
single_nat_gateway   = true # set false in prod for one NAT per AZ

# Security
allowed_http_cidrs = ["0.0.0.0/0"]
ssh_allowed_cidrs  = [] # keep empty and use SSM Session Manager
public_key_path    = "~/.ssh/asg-demo.pub"

# Launch template
instance_type              = "t3.micro"
ubuntu_version             = "24.04"
root_volume_size           = 10
enable_detailed_monitoring = true

# Auto Scaling group
asg_min_size              = 2
asg_desired_capacity      = 2
asg_max_size              = 4
health_check_type         = "EC2"
health_check_grace_period = 180
protect_from_scale_in     = false
cpu_target_percent        = 60
instance_warmup_seconds   = 120

# Application Load Balancer
alb_name                   = "alb"
app_port                   = 80
health_check_path          = "/"
enable_deletion_protection = false
