############################
# General
############################
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Project name, used as a prefix in resource names."
  type        = string
  default     = "asg-demo"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "owner" {
  description = "Owner tag (person or team)."
  type        = string
  default     = "devops"
}

############################
# Networking
############################
variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per Availability Zone (used by the ALB and NAT gateway)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per Availability Zone (used by the Auto Scaling group)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "single_nat_gateway" {
  description = "true = one shared NAT gateway (cheaper, fine for dev). false = one NAT per AZ (highly available, for prod)."
  type        = bool
  default     = true
}

############################
# Security
############################
variable "allowed_http_cidrs" {
  description = "CIDRs allowed to reach the ALB on port 80."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH to the instances. Empty = SSH closed (use SSM Session Manager). The instances are private, so SSH only works from inside the VPC (for example a bastion)."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.ssh_allowed_cidrs, "0.0.0.0/0")
    error_message = "Never open SSH to 0.0.0.0/0."
  }
}

variable "public_key_path" {
  description = "Path to your SSH PUBLIC key (.pub). Only the public half is uploaded; the private key never enters Terraform or Git."
  type        = string
  default     = "~/.ssh/asg-demo.pub"
}

############################
# Launch template
############################
variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "ubuntu_version" {
  description = "Ubuntu LTS release used for the AMI."
  type        = string
  default     = "24.04"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 10
}

variable "enable_detailed_monitoring" {
  description = "1-minute CloudWatch metrics (small extra cost). Lets scaling react in minutes instead of ~15 minutes."
  type        = bool
  default     = true
}

############################
# Auto Scaling group
############################
variable "asg_min_size" {
  description = "Minimum number of instances."
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Initial number of instances."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances."
  type        = number
  default     = 4
}

variable "health_check_type" {
  description = "EC2 = replace instances that fail EC2 status checks. ELB = also replace instances the load balancer marks unhealthy."
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "health_check_type must be EC2 or ELB."
  }
}

variable "health_check_grace_period" {
  description = "Seconds to wait after launch before health checks count (time for user data to finish)."
  type        = number
  default     = 180
}

variable "protect_from_scale_in" {
  description = "Protect instances from scale-in. Leave false unless instances hold work that must not be interrupted."
  type        = bool
  default     = false
}

variable "cpu_target_percent" {
  description = "Target average CPU utilization for the target tracking policy."
  type        = number
  default     = 60
}

variable "instance_warmup_seconds" {
  description = "Seconds a new instance is given to warm up before its metrics count toward scaling."
  type        = number
  default     = 120
}

############################
# Application Load Balancer
############################
variable "alb_name" {
  description = "Short name of the ALB (full name is <project>-<environment>-<alb_name>, max 32 chars)."
  type        = string
  default     = "alb"
}

variable "app_port" {
  description = "Port Nginx listens on (target port)."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "HTTP path used by the target group health check."
  type        = string
  default     = "/"
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion (set true in prod)."
  type        = bool
  default     = false
}
