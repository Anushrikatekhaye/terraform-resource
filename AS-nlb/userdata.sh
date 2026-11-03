#!/bin/bash
# -----------------------------------------------------------------------------
# userdata.sh - Runs once as root at first boot of every instance the ASG launches.
# Installs Nginx, publishes a welcome page showing this instance's identity and
# installs stress-ng for CPU load tests. Log: /var/log/user-data.log
# -----------------------------------------------------------------------------
set -euxo pipefail
exec > >(tee -a /var/log/user-data.log) 2>&1

export DEBIAN_FRONTEND=noninteractive

# Wait for the apt lock if unattended-upgrades is running at first boot.
APT_OPTS="-y -o DPkg::Lock::Timeout=300"
apt-get update ${APT_OPTS}
apt-get install ${APT_OPTS} nginx stress-ng curl

# Instance identity from IMDSv2 (token-based metadata service).
TOKEN=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
imds() {
  curl -fsS -H "X-aws-ec2-metadata-token: ${TOKEN}" "http://169.254.169.254/latest/meta-data/$1"
}

INSTANCE_ID=$(imds instance-id)
AZ=$(imds placement/availability-zone)
PRIVATE_IP=$(imds local-ipv4)
HOST_NAME=$(hostname)

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>NLB + Auto Scaling demo</title>
  <style>
    body { font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0;
           display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
    .card { background: #1e293b; padding: 2rem 3rem; border-radius: 12px; border-left: 6px solid #38bdf8; }
    h1 { margin-top: 0; }
    code { color: #38bdf8; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Welcome from ${HOST_NAME}</h1>
    <p>Instance ID: <code>${INSTANCE_ID}</code></p>
    <p>Availability Zone: <code>${AZ}</code></p>
    <p>Private IP: <code>${PRIVATE_IP}</code></p>
    <p>Served by Nginx behind an AWS Network Load Balancer.</p>
  </div>
</body>
</html>
HTML

# Hide the Nginx version in responses and headers.
sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf

nginx -t
systemctl enable nginx
systemctl restart nginx

echo "user-data finished OK on ${INSTANCE_ID}"
