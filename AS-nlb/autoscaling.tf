# -----------------------------------------------------------------------------
# autoscaling.tf - Auto Scaling Group and CPU target tracking scaling policy
# -----------------------------------------------------------------------------

resource "aws_autoscaling_group" "web" {
  name = "${local.name_prefix}-asg"

  min_size         = var.asg_min_size
  desired_capacity = var.asg_desired_capacity
  max_size         = var.asg_max_size

  # Instances run in the PRIVATE subnets, one or more per AZ.
  vpc_zone_identifier = [for s in aws_subnet.private : s.id]

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  # Registers every instance (now and in the future) with the NLB target group.
  target_group_arns = [aws_lb_target_group.web.arn]

  # ELB health check: an instance that fails the NLB health check is
  # terminated and replaced automatically (EC2 checks alone would miss a dead Nginx).
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period
  default_instance_warmup   = var.instance_warmup

  # Keep instances spread evenly across AZs (rebalances if one AZ gets heavy).
  availability_zone_distribution {
    capacity_distribution_strategy = "balanced-best-effort"
  }

  # On scale-in remove instances running the oldest template first, then the oldest instance.
  termination_policies = ["OldestLaunchTemplate", "OldestInstance"]

  # Make `terraform apply` wait until the minimum number of instances is healthy in the NLB.
  min_elb_capacity          = var.asg_min_size
  wait_for_capacity_timeout = "10m"

  # Rolling replacement when the launch template changes (new AMI, new user data).
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = var.instance_warmup
    }
  }

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  # Consistent tags on the ASG and (propagate_at_launch) on every instance.
  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "${local.name_prefix}-web" })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    # The scaling policy changes desired capacity at runtime; don't let the
    # next `terraform apply` reset it back to the value in tfvars.
    ignore_changes = [desired_capacity]

    precondition {
      condition     = var.asg_min_size <= var.asg_desired_capacity && var.asg_desired_capacity <= var.asg_max_size
      error_message = "Capacity must satisfy min <= desired <= max."
    }
  }

  # Explicit dependencies that Terraform cannot infer:
  #  - the target group must be attached to a load balancer (via the listener)
  #    before an ASG can register with it;
  #  - private subnets need their NAT route + route table association BEFORE the
  #    first instance boots, otherwise `apt install nginx` fails in user data.
  depends_on = [
    aws_lb_listener.tcp,
    aws_route.private_nat,
    aws_route_table_association.private,
  ]
}

# Target tracking policy: ASG creates and manages the CloudWatch alarms itself.
#  - Average CPU above 60%  -> alarm "AlarmHigh" -> scale OUT (add instances)
#  - Average CPU well below -> alarm "AlarmLow"  -> scale IN  (remove instances)
# Limits are always enforced: never below min_size (2), never above max_size (4).
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${local.name_prefix}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  estimated_instance_warmup = var.instance_warmup

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value     = var.target_cpu_utilization
    disable_scale_in = false # allow automatic scale-in when load drops
  }
}
