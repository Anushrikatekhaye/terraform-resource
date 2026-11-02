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
  nlb_name = "${local.name}-${var.nlb_name}"

  # One AZ per public subnet
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))

  # { "web-1" = 0, "web-2" = 1 } -> used by for_each and to pick a subnet
  instances = { for index, name in var.instance_names : name => index }
}

# Fail the plan early (as a warning) if the inputs do not line up
check "inputs_consistent" {
  assert {
    condition     = length(var.public_subnet_cidrs) == length(var.private_subnet_cidrs)
    error_message = "public_subnet_cidrs and private_subnet_cidrs should have the same number of entries (one per AZ)."
  }

  assert {
    condition     = length(var.instance_names) <= length(var.public_subnet_cidrs) * 2
    error_message = "Too many instances for the number of subnets; add subnets or reduce instance_names."
  }
}
