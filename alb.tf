############################
# Application Load Balancer (internet-facing, across both public subnets)
############################
resource "aws_lb" "web" {
  name               = local.alb_name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  idle_timeout               = 60
  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection

  tags = { Name = local.alb_name }
}

############################
# Target group: HTTP :80, health check on "/"
# The ALB only sends traffic to targets that pass this check.
############################
resource "aws_lb_target_group" "web" {
  name_prefix = "web-"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  port        = var.app_port
  protocol    = "HTTP"

  # Seconds the ALB keeps an instance that is shutting down while in-flight requests finish
  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = var.health_check_path
    port                = "traffic-port"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.alb_name}-tg" }

  lifecycle {
    create_before_destroy = true
  }
}

############################
# HTTP listener on port 80 -> forward to the target group
############################
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  tags = { Name = "${local.alb_name}-listener-80" }
}
