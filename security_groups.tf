############################
# ALB security group: the only thing exposed to the internet
############################
resource "aws_security_group" "alb" {
  name_prefix = "${local.alb_name}-"
  description = "ALB: HTTP from allowed CIDRs"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.alb_name}-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = toset(var.allowed_http_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from clients"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Least privilege: the ALB may only talk to the instances on the app port
resource "aws_vpc_security_group_egress_rule" "alb_to_instances" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB to instances (traffic and health checks)"
  referenced_security_group_id = aws_security_group.instances.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

############################
# Instance security group (separate from the ALB one)
# Only the ALB can reach Nginx. Nothing from the internet reaches the instances.
############################
resource "aws_security_group" "instances" {
  name_prefix = "${local.name}-instances-"
  description = "ASG instances: app port from the ALB only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-instances-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "instances_from_alb" {
  security_group_id            = aws_security_group.instances.id
  description                  = "App port from the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# Optional SSH: no rules are created while ssh_allowed_cidrs is empty
resource "aws_vpc_security_group_ingress_rule" "instances_ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.instances.id
  description       = "SSH from trusted CIDR"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# Outbound goes through the NAT gateway: apt (HTTP/HTTPS) and the SSM agent (HTTPS)
resource "aws_vpc_security_group_egress_rule" "instances_https_out" {
  security_group_id = aws_security_group.instances.id
  description       = "HTTPS out (SSM agent, package repos)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "instances_http_out" {
  security_group_id = aws_security_group.instances.id
  description       = "HTTP out (apt mirrors)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}
