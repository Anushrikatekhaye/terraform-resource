############################
# Shared data and locals used by the other files
############################
data "aws_availability_zones" "available" {
  state = "available"
}

# Canonical publishes the current Ubuntu AMI ID in a public SSM parameter,
# so we never hardcode an AMI ID.
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/${var.ubuntu_version}/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  name     = "${var.project}-${var.environment}"
  alb_name = "${local.name}-${var.alb_name}"

  # One AZ per public subnet
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))

  # Number of NAT gateways: 1 shared, or 1 per AZ
  nat_count = var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)

  # Standard tags: used by the provider default_tags, the launch template and the ASG
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}

# Warn at plan time if the inputs do not line up
check "inputs_consistent" {
  assert {
    condition     = length(var.public_subnet_cidrs) == length(var.private_subnet_cidrs)
    error_message = "public_subnet_cidrs and private_subnet_cidrs must have the same number of entries (one per AZ)."
  }

  assert {
    condition     = var.asg_min_size <= var.asg_desired_capacity && var.asg_desired_capacity <= var.asg_max_size
    error_message = "Capacity must satisfy min <= desired <= max."
  }

  assert {
    condition     = var.asg_min_size >= 2
    error_message = "Keep at least 2 instances (one per AZ) for high availability."
  }
}
