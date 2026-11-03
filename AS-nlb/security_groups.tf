# -----------------------------------------------------------------------------
# security_groups.tf - Two separate security groups (least privilege):
#
#   Internet --80--> [ NLB SG ] --80--> [ EC2 SG ] --80/443--> NAT --> Internet
#
# The NLB target group has client IP preservation DISABLED (see nlb.tf), so the
# instances see the NLB as the source of traffic and health checks. That lets
# the EC2 security group allow port 80 ONLY from the NLB security group.
# -----------------------------------------------------------------------------

# ----- NLB security group ----------------------------------------------------

resource "aws_security_group" "nlb" {
  name_prefix = "${local.name_prefix}-nlb-sg-"
  description = "Network Load Balancer: public HTTP in, traffic to web instances out"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-nlb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_http" {
  for_each = toset(var.allowed_http_cidrs)

  security_group_id = aws_security_group.nlb.id
  description       = "Application traffic from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.app_port
  to_port           = var.app_port
}

# The NLB may only talk to the web instances (traffic + health checks).
resource "aws_vpc_security_group_egress_rule" "nlb_to_ec2" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "To web instances"
  referenced_security_group_id = aws_security_group.ec2.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

# ----- EC2 (web server) security group --------------------------------------

resource "aws_security_group" "ec2" {
  name_prefix = "${local.name_prefix}-ec2-sg-"
  description = "Web instances: HTTP from the NLB only, SSH from trusted CIDRs only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-ec2-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_http_from_nlb" {
  security_group_id            = aws_security_group.ec2.id
  description                  = "HTTP from the NLB (traffic and health checks)"
  referenced_security_group_id = aws_security_group.nlb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

resource "aws_vpc_security_group_ingress_rule" "ec2_ssh" {
  for_each = toset(local.ssh_cidrs)

  security_group_id = aws_security_group.ec2.id
  description       = "SSH from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# Outbound: only what the instances need - package downloads (80/443) and
# SSM over 443. DNS to the VPC resolver is not filtered by security groups.
resource "aws_vpc_security_group_egress_rule" "ec2_outbound" {
  for_each = {
    http  = 80
    https = 443
  }

  security_group_id = aws_security_group.ec2.id
  description       = "Outbound ${each.key} via NAT Gateway"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
}
