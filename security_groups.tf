############################
# NLB security group
# NLBs support security groups, so we can control who reaches the listener.
############################
resource "aws_security_group" "nlb" {
  name_prefix = "${local.nlb_name}-"
  description = "Network Load Balancer: TCP listener from allowed client CIDRs"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.nlb_name}-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_listener" {
  for_each = toset(var.allowed_client_cidrs)

  security_group_id = aws_security_group.nlb.id
  description       = "Clients to NLB listener"
  cidr_ipv4         = each.value
  from_port         = var.listener_port
  to_port           = var.listener_port
  ip_protocol       = "tcp"
}

# Least privilege: the NLB may only send traffic to the instances on the app port
resource "aws_vpc_security_group_egress_rule" "nlb_to_instances" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "NLB to instances (traffic and health checks)"
  referenced_security_group_id = aws_security_group.instances.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

############################
# Instance security group
# Only the NLB can reach Nginx. The instances are not directly reachable from the internet.
############################
resource "aws_security_group" "instances" {
  name_prefix = "${local.name}-instances-"
  description = "Nginx instances: app port from the NLB only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-instances-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# Works because the target group has client IP preservation turned off,
# so traffic arrives from the NLB (and its security group), not from the client.
resource "aws_vpc_security_group_ingress_rule" "instances_from_nlb" {
  security_group_id            = aws_security_group.instances.id
  description                  = "App port from the NLB"
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# Outbound is needed for apt (Nginx install) and the SSM agent. No NAT here,
# so the instances sit in public subnets and use the internet gateway.
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
