# -----------------------------------------------------------------------------
# variables.tf - Input variables (values live in terraform.tfvars)
# -----------------------------------------------------------------------------

# ----- General ---------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short project name used as a prefix for resource names and in tags."
  type        = string
  default     = "nlb-asg"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner tag value (your name or team)."
  type        = string
  default     = "devops-team"
}

# ----- Networking ------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (one per Availability Zone)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Provide exactly two public subnet CIDRs."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets (one per Availability Zone)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Provide exactly two private subnet CIDRs."
  }
}

variable "single_nat_gateway" {
  description = "true = one shared NAT Gateway (cheaper, single point of failure). false = one NAT Gateway per AZ (highly available)."
  type        = bool
  default     = true
}

# ----- Security --------------------------------------------------------------

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed to reach the NLB on the application port."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH to the instances. Empty = only from inside the VPC (e.g. via a bastion). Prefer SSM Session Manager."
  type        = list(string)
  default     = []
}

variable "ssh_public_key_path" {
  description = "Path to the PUBLIC SSH key uploaded as the EC2 key pair. The private key never goes into Terraform or Git."
  type        = string
  default     = "~/.ssh/aws-nlb-demo.pub"
}

# ----- Compute ---------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for the web servers."
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "Optional AMI override. Empty = latest Ubuntu Server 24.04 LTS from Canonical."
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 8
}

variable "cpu_credits" {
  description = "T-family CPU credit mode: 'unlimited' (no throttling during load tests) or 'standard' (hard cost cap)."
  type        = string
  default     = "unlimited"

  validation {
    condition     = contains(["standard", "unlimited"], var.cpu_credits)
    error_message = "cpu_credits must be 'standard' or 'unlimited'."
  }
}

variable "enable_detailed_monitoring" {
  description = "Publish EC2 metrics every 1 minute instead of 5 (faster scaling reactions, small extra cost)."
  type        = bool
  default     = true
}

# ----- Load balancer ---------------------------------------------------------

variable "app_port" {
  description = "Port Nginx listens on and the NLB listener/target group use."
  type        = number
  default     = 80
}

variable "enable_deletion_protection" {
  description = "Protect the NLB from accidental deletion. Set false for easy terraform destroy in a lab."
  type        = bool
  default     = false
}

# ----- Auto Scaling ----------------------------------------------------------

variable "asg_min_size" {
  description = "Minimum number of instances."
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Initial desired number of instances."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances."
  type        = number
  default     = 4
}

variable "health_check_grace_period" {
  description = "Seconds the ASG waits after launch before it starts evaluating ELB health (must cover apt install + Nginx start)."
  type        = number
  default     = 300
}

variable "target_cpu_utilization" {
  description = "Target average CPU utilization (%) for the target tracking scaling policy."
  type        = number
  default     = 60

  validation {
    condition     = var.target_cpu_utilization > 0 && var.target_cpu_utilization < 100
    error_message = "target_cpu_utilization must be between 1 and 99."
  }
}

variable "instance_warmup" {
  description = "Seconds a new instance is given to warm up before its metrics count toward scaling decisions."
  type        = number
  default     = 120
}
