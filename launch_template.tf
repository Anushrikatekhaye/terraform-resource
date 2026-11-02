############################
# SSH key pair: only the PUBLIC key is uploaded.
# Create it locally first:  ssh-keygen -t ed25519 -f ~/.ssh/asg-demo -C asg-demo
############################
resource "aws_key_pair" "this" {
  key_name   = "${local.name}-key"
  public_key = file(pathexpand(var.public_key_path))

  tags = { Name = "${local.name}-key" }
}

############################
# IAM: SSM Session Manager (shell access to private instances with no bastion)
############################
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${local.name}-ec2-role"
  description        = "Lets the ASG instances register with SSM Session Manager"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

############################
# Launch template: the blueprint every ASG instance is created from
############################
resource "aws_launch_template" "web" {
  name_prefix            = "${local.name}-lt-"
  description            = "Ubuntu ${var.ubuntu_version} with Nginx for the ${local.name} ASG"
  image_id               = nonsensitive(data.aws_ssm_parameter.ubuntu_ami.value)
  instance_type          = var.instance_type
  key_name               = aws_key_pair.this.key_name
  ebs_optimized          = true
  vpc_security_group_ids = [aws_security_group.instances.id]
  update_default_version = true

  # userdata.sh is read as-is (no Terraform variables inside) and base64 encoded
  user_data = filebase64("${path.module}/userdata.sh")

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  # IMDSv2 only (blocks SSRF-style credential theft)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Detailed (1-minute) CloudWatch metrics so scaling reacts quickly
  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Tags copied onto every instance and volume the ASG launches
  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name}-web" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name}-web-vol" })
  }

  tags = { Name = "${local.name}-lt" }

  lifecycle {
    create_before_destroy = true
  }
}
