############################
# Auto Scaling group
############################
resource "aws_autoscaling_group" "web" {
  name = "${local.name}-asg"

  min_size         = var.asg_min_size
  desired_capacity = var.asg_desired_capacity
  max_size         = var.asg_max_size

  # Instances run in the PRIVATE subnets, one or more per AZ
  vpc_zone_identifier = aws_subnet.private[*].id

  # Attaching the target group makes the ASG register new instances with the ALB
  # automatically and deregister (drain) instances it terminates.
  target_group_arns = [aws_lb_target_group.web.arn]

  # EC2 = replace instances that fail EC2 status checks (hardware or OS failure).
  # ELB would also replace instances the ALB marks unhealthy (application failure).
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  # Seconds before a new instance's metrics count toward scaling decisions
  default_instance_warmup = var.instance_warmup_seconds

  # Only enable when instances hold work that must not be interrupted
  protect_from_scale_in = var.protect_from_scale_in

  # Keep instances evenly spread across AZs when launching and rebalancing
  availability_zone_distribution {
    capacity_distribution_strategy = "balanced-best-effort"
  }

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  # Group metrics in CloudWatch (desired, in-service, pending...) for dashboards and debugging
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  # When the launch template changes, replace instances gradually
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  # Tag the instances (for_each over the shared tag map)
  dynamic "tag" {
    for_each = merge(local.tags, { Name = "${local.name}-web" })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  # Instances need the NAT route to download Nginx during user data
  depends_on = [aws_route.private_nat]

  lifecycle {
    # The scaling policy changes desired capacity; do not let Terraform reset it
    ignore_changes = [desired_capacity]
  }
}

############################
# Dynamic scaling: target tracking on average CPU
# One policy handles BOTH directions. AWS creates and manages the CloudWatch alarms:
#   - scale OUT when average CPU stays above the target
#   - scale IN when it stays well below it (never below min_size)
############################
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${local.name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value     = var.cpu_target_percent
    disable_scale_in = false
  }
}
