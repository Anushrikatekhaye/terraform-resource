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
  default     = "nlb-demo"
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
  description = "Public subnet CIDRs, one per Availability Zone."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per Availability Zone."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

############################
# Network Load Balancer
############################
variable "nlb_name" {
  description = "Short name of the NLB (the full name is <project>-<environment>-<nlb_name>, max 32 chars)."
  type        = string
  default     = "nlb"
}

variable "listener_port" {
  description = "TCP port the NLB listens on."
  type        = number
  default     = 80
}

variable "allowed_client_cidrs" {
  description = "CIDRs allowed to reach the NLB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_cross_zone_load_balancing" {
  description = "Distribute traffic evenly across targets in all AZs."
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Protect the NLB from accidental deletion (set true in prod)."
  type        = bool
  default     = false
}

############################
# Target group / health check
############################
variable "app_port" {
  description = "Port Nginx listens on (target port and health check port)."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "HTTP path used by the health check."
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "Seconds between health checks."
  type        = number
  default     = 10
}

variable "health_check_threshold" {
  description = "Consecutive checks to mark a target healthy or unhealthy (NLB requires both to match)."
  type        = number
  default     = 3
}

############################
# EC2
############################
variable "instance_names" {
  description = "One EC2 instance is created per name. Instances are spread across the public subnets in order."
  type        = list(string)
  default     = ["web-1", "web-2"]
}

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
