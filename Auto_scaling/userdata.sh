#!/bin/bash
# EC2 initialization script (runs once as root at first boot via cloud-init).
# Output is logged to /var/log/cloud-init-output.log
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1. Install Nginx
apt-get update -y
apt-get install -y nginx

# 2. Collect details for the welcome page (IMDSv2: get a token first)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
HOST_NAME=$(hostname)

# 3. Custom welcome page showing which instance answered
cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>
  <head><title>$HOST_NAME</title></head>
  <body style="font-family: sans-serif; text-align: center; margin-top: 12%;">
    <h1>Hello from $HOST_NAME</h1>
    <p>Instance ID: $INSTANCE_ID</p>
    <p>Availability Zone: $AZ</p>
    <p>Private IP: $PRIVATE_IP</p>
    <p>Served by an Auto Scaling group behind an Application Load Balancer</p>
  </body>
</html>
HTML

# 4. Start Nginx now and on every reboot
systemctl enable --now nginx
