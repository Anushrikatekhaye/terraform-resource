# Troubleshooting guide

Handy variables (see `docs/TESTING.md`): `$NLB`, `$TG_ARN`, `$ASG`, `$AWS_REGION`.

General rule: follow the traffic path **client → NLB SG → listener → target group → EC2 SG → Nginx** and find the first hop that fails.

---

## 1. NLB targets show `unhealthy`

Find the reason first:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' --output table
```

| Reason | Likely cause | Fix |
|--------|--------------|-----|
| `Target.FailedHealthChecks` / timeout | Nginx not running, wrong port, or SG blocks the NLB | Check Nginx (scenario 6) and the instance security group allows port 80 **from the NLB security group** |
| `Target.ResponseCodeMismatch` | `/` returns something other than 200-399 | `curl -i localhost` on the instance; check the Nginx config |
| `Target.NotInUse` / `Target.InvalidState` | Instance not in a subnet of an enabled AZ, or being terminated | Make sure the NLB has a subnet in each AZ where instances run |
| `Elb.InitialHealthChecking` | Still in the first checks | Wait about 30 s after Nginx is up |

Also remember: if **all** targets are unhealthy, an NLB *fails open* and sends traffic to all of them anyway, so you can see odd behaviour instead of a clean error.

## 2. NLB returns connection timeout

1. Is the NLB `active`? `aws elbv2 describe-load-balancers --names <name> --query 'LoadBalancers[0].State'`. New NLBs take a few minutes; DNS may take longer.
2. NLB security group allows inbound TCP 80 from your IP/CIDR (`allowed_http_cidrs`)?
3. Listener port matches what you request (`:80`)? `aws elbv2 describe-listeners --load-balancer-arn <arn>`.
4. Is the NLB in **public** subnets whose route table has `0.0.0.0/0 → igw`? (scenario 8)
5. Any healthy target at all? (scenario 1)
6. Corporate firewall/VPN blocking outbound port 80? Test from another network or from `curl` in CloudShell.

## 3. Auto Scaling Group is not launching instances

```bash
aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG" --max-items 5 \
  --query 'Activities[].[StatusCode,StatusMessage]' --output text
```

Common messages and fixes:

- *Your requested instance type is not supported in the AZ / insufficient capacity* → try another instance type or add subnets in other AZs.
- *The key pair does not exist* or *invalid AMI* → verify the launch template (scenario 10).
- *You have requested more instances than your quota* → check EC2 vCPU service quotas.
- *Invalid IAM Instance Profile* → the profile was just created; retry after a minute or check `terraform state show aws_iam_instance_profile.ec2`.
- Desired capacity already equals max, or the ASG is suspended: `aws autoscaling describe-auto-scaling-groups ... --query 'AutoScalingGroups[0].SuspendedProcesses'`.
- Instances launch and are immediately replaced in a loop → they fail ELB health checks (scenarios 5, 6).

## 4. CloudWatch scaling policy is not triggering

1. Alarm state: `aws cloudwatch describe-alarms --alarm-name-prefix "TargetTracking-$ASG"`. `INSUFFICIENT_DATA` means no metrics yet.
2. Remember it is an **average across the group**: one instance at 100% and one idle = 50% < 60%. Load every instance.
3. Timing: scale-out needs 3 consecutive 1-minute datapoints (15 min with basic 5-minute monitoring). Scale-in needs 15 low datapoints.
4. Warmup: newly launched instances are excluded from the metric for `instance_warmup` seconds.
5. Already at `max_size`? The ASG cannot go beyond 4. Check `describe-scaling-activities`.
6. T3 credit throttling: with `cpu_credits = "standard"` and exhausted credits, CPU is capped near 10% and never reaches the target. Use `unlimited` for load tests.
7. Is the policy attached? `aws autoscaling describe-policies --auto-scaling-group-name "$ASG"`.

## 5. EC2 instances fail health checks

Is it the EC2 check or the ELB check?

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,HealthStatus,LifecycleState]' --output table
```

- Terminated right after launch and replaced repeatedly: the grace period (300 s) is too short or user data failed. Check `/var/log/user-data.log` (scenario 6).
- Instance healthy in EC2 but unhealthy in ELB: scenario 1.
- Quick way to keep an instance for debugging: `aws autoscaling set-instance-health --instance-id <id> --health-status Healthy` or temporarily suspend `ReplaceUnhealthy`.

## 6. Nginx does not start through user data

Connect with SSM (`aws ssm start-session --target <id>`), then:

```bash
sudo cat /var/log/user-data.log           # our script output (set -x shows every command)
sudo cat /var/log/cloud-init-output.log   # cloud-init's own log
sudo cloud-init status --long
sudo systemctl status nginx --no-pager
sudo nginx -t                             # config syntax
sudo ss -tlnp | grep ':80'                # is something listening?
curl -I http://localhost
```

Typical causes:

- `apt-get update` fails → **no outbound internet**: private route table has no `0.0.0.0/0 → NAT`, NAT Gateway not available, or the EC2 SG blocks outbound 80/443 (scenario 8/9).
- `Could not get lock /var/lib/dpkg/lock` → handled by `DPkg::Lock::Timeout`; if it still happens, retry `sudo apt-get install nginx`.
- Script has Windows line endings (`\r`) → `file userdata.sh` should not say CRLF; fix with `dos2unix userdata.sh`.
- Missing `#!/bin/bash` first line → cloud-init treats it as not a script.
- To re-run user data on a test instance: `sudo cloud-init clean --logs && sudo cloud-init init && sudo cloud-init modules --mode=final`.

## 7. Instances do not register with the target group

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].TargetGroupARNs'
```

- Empty → the ASG is not attached. Confirm `target_group_arns` in `autoscaling.tf`.
- Terraform error *target group does not have an associated load balancer* → the ASG was created before the listener; keep `depends_on = [aws_lb_listener.tcp]`.
- Instance launched but missing in the target group → look at the ASG activity: it may have failed or been terminated before registration; check the lifecycle state is `InService`.
- Instance shows `unused` → its AZ/subnet has no NLB node. NLB subnets must cover every AZ the ASG uses.

## 8. Incorrect subnet or route table configuration

```bash
terraform state list | grep -E 'route|subnet'
aws ec2 describe-route-tables --filters Name=vpc-id,Values=$(terraform output -raw vpc_id) \
  --query 'RouteTables[].[Tags[?Key==`Name`]|[0].Value,Routes[].[DestinationCidrBlock,GatewayId,NatGatewayId,State]]' --output json
```

What it should look like:

| Subnet | Default route |
|--------|---------------|
| Public (NLB, NAT) | `0.0.0.0/0 → igw-…` |
| Private (instances) | `0.0.0.0/0 → nat-…` (state `active`, not `blackhole`) |

Symptoms: NLB timeout (public subnet without IGW route); `apt` fails (private subnet without NAT route); NAT Gateway placed in a private subnet (it must be public); subnet not associated with the intended route table (it silently uses the VPC main route table).

## 9. Security group blocking traffic

```bash
aws ec2 describe-security-groups --group-ids <ec2-sg-id> <nlb-sg-id> \
  --query 'SecurityGroups[].[GroupName,IpPermissions,IpPermissionsEgress]' --output json
```

Checklist:

- NLB SG ingress: TCP 80 from your client CIDR. NLB SG egress: TCP 80 to the EC2 SG.
- EC2 SG ingress: TCP 80 **from the NLB SG**. This only works because `preserve_client_ip = false`; if you enable client IP preservation, instances see the visitor's IP and the SG rule must allow client CIDRs instead.
- EC2 SG egress: 80 and 443 to `0.0.0.0/0` (needed for apt and SSM).
- Use VPC Reachability Analyzer (VPC console) between the NLB ENI and an instance for a definitive answer.

## 10. Launch Template configuration errors

```bash
aws ec2 describe-launch-template-versions --launch-template-id "$(terraform output -raw launch_template_id)" \
  --versions '$Latest' --query 'LaunchTemplateVersions[0].LaunchTemplateData' --output json
```

Typical problems:

- **Wrong AMI for the region** or deprecated AMI → use the data source (default) instead of hardcoding.
- **Key pair missing** → it must exist in the same region (Terraform creates it from `ssh_public_key_path`).
- **Invalid user data**: it must be base64 (`filebase64`), under 16 KB, and start with `#!`.
- **Instance type not available in the AZ** → `aws ec2 describe-instance-type-offerings --location-type availability-zone --filters Name=instance-type,Values=t3.micro`.
- **Root device name**: Ubuntu AMIs use `/dev/sda1`; a wrong `device_name` creates an extra volume instead of resizing the root volume.
- **Security group from a different VPC** than the subnets.
- Changed the template but nothing happened → `instance_refresh` replaces instances gradually; check `aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG"`.
