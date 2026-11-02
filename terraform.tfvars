# Values for this deployment. No secrets here, so this file is safe to commit.
aws_region  = "ap-south-1"
project     = "nlb-demo"
environment = "dev"
owner       = "devops"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# Network Load Balancer
nlb_name                         = "nlb"
listener_port                    = 80
allowed_client_cidrs             = ["0.0.0.0/0"]
enable_cross_zone_load_balancing = true
enable_deletion_protection       = false

# Target group and health check
app_port               = 80
health_check_path      = "/"
health_check_interval  = 10
health_check_threshold = 3

# EC2
instance_names   = ["web-1", "web-2"]
instance_type    = "t3.micro"
ubuntu_version   = "24.04"
root_volume_size = 10
