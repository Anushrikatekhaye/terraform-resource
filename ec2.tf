############################
# IAM: SSM Session Manager (shell access with no SSH key and no port 22)
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
  description        = "Lets the instances register with SSM Session Manager"
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
# Two Ubuntu instances running Nginx, one per public subnet (one per AZ)
############################
resource "aws_instance" "web" {
  for_each = local.instances

  ami                         = nonsensitive(data.aws_ssm_parameter.ubuntu_ami.value)
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[each.value % length(aws_subnet.public)].id
  vpc_security_group_ids      = [aws_security_group.instances.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true # needed to reach the internet gateway for apt (no NAT)
  ebs_optimized               = true

  # Each instance writes its own welcome page so you can see which one answered
  user_data = <<-EOT
    #!/bin/bash
    set -eux
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y nginx

    # Instance metadata (IMDSv2) for the page content
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

    cat > /var/www/html/index.html <<HTML
    <html>
      <head><title>${each.key}</title></head>
      <body style="font-family: sans-serif; text-align: center; margin-top: 15%;">
        <h1>Welcome to ${each.key}</h1>
        <p>Instance: $INSTANCE_ID</p>
        <p>Availability Zone: $AZ</p>
        <p>Served through the AWS Network Load Balancer</p>
      </body>
    </html>
    HTML

    systemctl enable --now nginx
  EOT

  # Re-run the script if you edit it
  user_data_replace_on_change = true

  # IMDSv2 only (blocks SSRF-style credential theft)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${local.name}-${each.key}" }

  # Routes must exist before user data tries to run apt-get
  depends_on = [aws_route.public_internet]
}
