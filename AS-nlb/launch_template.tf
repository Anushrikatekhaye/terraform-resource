# -----------------------------------------------------------------------------
# launch_template.tf - The "recipe" the Auto Scaling Group uses for every instance
# -----------------------------------------------------------------------------

resource "aws_launch_template" "web" {
  name_prefix   = "${local.name_prefix}-lt-"
  description   = "Ubuntu 24.04 + Nginx web server"
  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.ec2.key_name

  vpc_security_group_ids = [aws_security_group.ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  # Runs once at first boot: installs and configures Nginx (see userdata.sh).
  user_data = filebase64("${path.module}/userdata.sh")

  # 1-minute CloudWatch metrics so target tracking reacts quickly.
  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  credit_specification {
    cpu_credits = var.cpu_credits
  }

  # IMDSv2 only: blocks SSRF-style credential theft through the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/sda1" # root device name on Ubuntu AMIs

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Tags copied onto instances and volumes created from this template.
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-web"
      Role = "web-server"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-web-root"
    })
  }

  # Make every new template version the default so "$Default" is always current.
  update_default_version = true

  lifecycle {
    create_before_destroy = true
  }
}
