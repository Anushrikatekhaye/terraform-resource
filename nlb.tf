############################
# Network Load Balancer (Layer 4, internet-facing)
############################
resource "aws_lb" "nlb" {
  name               = local.nlb_name
  load_balancer_type = "network"
  internal           = false
  security_groups    = [aws_security_group.nlb.id]
  subnets            = aws_subnet.public[*].id # one subnet per AZ -> one NLB node per AZ

  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  enable_deletion_protection       = var.enable_deletion_protection

  tags = { Name = local.nlb_name }
}

############################
# Target group: TCP to port 80, HTTP health check
############################
resource "aws_lb_target_group" "nginx" {
  name_prefix = "nginx-"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  port        = var.app_port
  protocol    = "TCP"

  # Fast drain when an instance is removed
  deregistration_delay = 30

  # Off, so traffic reaches the instances from the NLB and the instance
  # security group can allow the NLB security group (least privilege).
  preserve_client_ip = false

  health_check {
    enabled             = true
    protocol            = "HTTP" # TCP target group, but an HTTP check validates that Nginx really responds
    port                = tostring(var.app_port)
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = var.health_check_interval
    healthy_threshold   = var.health_check_threshold
    unhealthy_threshold = var.health_check_threshold # NLB requires the two thresholds to match
  }

  tags = { Name = "${local.nlb_name}-tg" }

  lifecycle {
    create_before_destroy = true
  }
}

############################
# Register both instances as targets (for_each: one attachment per instance)
############################
resource "aws_lb_target_group_attachment" "web" {
  for_each = aws_instance.web

  target_group_arn = aws_lb_target_group.nginx.arn
  target_id        = each.value.id
  port             = var.app_port
}

############################
# TCP listener -> forward to the target group
############################
resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx.arn
  }

  tags = { Name = "${local.nlb_name}-listener-${var.listener_port}" }
}
