# -----------------------------------------------------------------------------
# nlb.tf - Internet-facing Network Load Balancer, target group and listener
# -----------------------------------------------------------------------------

resource "aws_lb" "nlb" {
  name               = "${local.name_prefix}-nlb"
  load_balancer_type = "network"
  internal           = false # internet-facing

  # One NLB node per public subnet (one per AZ).
  subnets = [for s in aws_subnet.public : s.id]

  security_groups = [aws_security_group.nlb.id]

  # Every NLB node can send traffic to targets in ALL enabled AZs.
  enable_cross_zone_load_balancing = true

  enable_deletion_protection = var.enable_deletion_protection

  tags = {
    Name = "${local.name_prefix}-nlb"
  }

  # An internet-facing load balancer needs the Internet Gateway attached first.
  depends_on = [aws_internet_gateway.main]
}

resource "aws_lb_target_group" "web" {
  name        = "${local.name_prefix}-tg"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  protocol    = "TCP"
  port        = var.app_port

  # Source IP seen by instances = NLB node, which allows the EC2 security group
  # to reference the NLB security group instead of opening port 80 to the world.
  preserve_client_ip = false

  # Give in-flight connections time to finish when an instance is removed.
  deregistration_delay = 60

  # The listener is TCP, but health checks are HTTP: a 200 from Nginx proves
  # the application works, not just that port 80 accepts connections.
  health_check {
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/"
    matcher             = "200-399"
    interval            = 10 # NLB HTTP health checks allow 10 or 30 seconds
    healthy_threshold   = 3  # NLB requires healthy and unhealthy thresholds to be equal
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${local.name_prefix}-tg"
  }
}

resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.app_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  tags = {
    Name = "${local.name_prefix}-listener-tcp-${var.app_port}"
  }
}
