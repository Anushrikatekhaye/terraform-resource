# -----------------------------------------------------------------------------
# main.tf - Shared building blocks: data sources, locals, IAM and the key pair.
# Network, security, compute and load balancing live in their own files.
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"

  # Skip Local Zones / Wavelength Zones.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Latest Ubuntu Server 24.04 LTS (Noble) x86_64 AMI published by Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Tags applied to everything (provider default_tags + ASG/instance tags).
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }

  # Use the first two Availability Zones of the region.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Maps keyed by AZ name so resources can use for_each (stable, readable addresses).
  public_subnets  = { for i, az in local.azs : az => var.public_subnet_cidrs[i] }
  private_subnets = { for i, az in local.azs : az => var.private_subnet_cidrs[i] }

  # Which AZs get a NAT Gateway: just the first one (cheap) or all (HA).
  nat_azs = var.single_nat_gateway ? [local.azs[0]] : local.azs

  # SSH is only reachable from inside the VPC unless explicit CIDRs are provided.
  ssh_cidrs = length(var.ssh_allowed_cidrs) > 0 ? var.ssh_allowed_cidrs : [var.vpc_cidr]

  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
}

# -----------------------------------------------------------------------------
# IAM - instance role + profile.
# Only AmazonSSMManagedInstanceCore is attached (Session Manager shell access
# without opening SSH to the internet). Nothing else: least privilege.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# -----------------------------------------------------------------------------
# SSH key pair - only the PUBLIC key is uploaded. Generate the pair locally:
#   ssh-keygen -t ed25519 -f ~/.ssh/aws-nlb-demo -N ""
# -----------------------------------------------------------------------------

resource "aws_key_pair" "ec2" {
  key_name   = "${local.name_prefix}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}
