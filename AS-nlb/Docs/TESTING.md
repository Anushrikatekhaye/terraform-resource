# Testing and validation

Run these after `terraform apply`. Replace the region if you changed it.

```bash
export AWS_REGION=ap-south-1
export NLB=$(terraform output -raw nlb_dns_name)
export TG_ARN=$(terraform output -raw target_group_arn)
export ASG=$(terraform output -raw autoscaling_group_name)
```

## 1-2. Access the NLB and verify the Nginx page

Open `http://<nlb_dns_name>` in a browser (new NLBs can take a few minutes before DNS and targets are ready). Or:

```bash
curl -i "http://$NLB"
```

Expected: `HTTP/1.1 200 OK` and a page saying "Welcome from ip-10-0-…".

## 3. Observe different instances

A browser reuses its TCP connection (keep-alive), and an NLB balances per **connection**, so refreshing may keep hitting the same instance. Use curl, which opens a new connection each time, or hard-refresh in a private window:

```bash
for i in $(seq 1 20); do curl -s "http://$NLB" | grep -o 'Welcome from [^<]*'; done | sort | uniq -c
```

Expected: two different hostnames, roughly balanced.

## 4. Check target health

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' --output table
```

Expected: every target `healthy`. (`initial` = still in the first health checks, `unhealthy` → see the troubleshooting guide.)

## 5. Generate CPU load

Connect to an instance with SSM Session Manager (no SSH needed; needs the Session Manager plugin for the AWS CLI, or use the EC2 console → Connect → Session Manager):

```bash
terraform output -raw list_instances_command | bash       # find instance IDs
aws ssm start-session --target i-0123456789abcdef0
```

Inside the instance (`stress-ng` is installed by user data):

```bash
# Use all vCPUs at 100% for 15 minutes
sudo stress-ng --cpu 0 --cpu-method matrixprod --timeout 900s --metrics-brief
```

Alternative without extra packages: `yes > /dev/null &` once per vCPU (`nproc`), stop with `pkill yes`.

Load only one instance: that is enough, because the policy tracks the **average** across the group. One instance at 100% and one idle averages about 50%. To cross 60%, load **both** instances (run the command in two sessions), or lower `target_cpu_utilization` temporarily.

Monitor on the instance in a second session:

```bash
top -b -n 1 | head -15     # CPU usage per process
uptime                      # load average
vmstat 5                    # CPU/memory/IO every 5 s (Ctrl+C to stop)
nproc                       # number of vCPUs
sudo systemctl status nginx --no-pager
sudo tail -n 20 /var/log/user-data.log
```

## 6. Monitor CPU in CloudWatch

Console: CloudWatch → Metrics → EC2 → By Auto Scaling Group → `CPUUtilization` for your ASG. Or CLI:

```bash
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value="$ASG" \
  --start-time "$(date -u -d '-30 minutes' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
  --period 60 --statistics Average \
  --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Average]' --output table
```

(`date -d` is GNU/Linux syntax; on macOS use `date -u -v-30M +%FT%TZ`.)

Check the alarms that the policy created:

```bash
aws cloudwatch describe-alarms --alarm-name-prefix "TargetTracking-$ASG" \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output table
```

`AlarmHigh` should move to `ALARM` after about 3 minutes of sustained load.

## 7. Verify scale-out

```bash
aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG" --max-items 5 \
  --query 'Activities[].[StartTime,StatusCode,Description,Cause]' --output table

aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' --output text
```

Expected: desired capacity rises above 2 (never above 4) and new instances appear in the activity list.

## 8. New instances register automatically

```bash
watch -n 10 "aws elbv2 describe-target-health --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output text"
```

Expected: new instance IDs show `initial`, then `healthy` after about 30 s of passing health checks (once Nginx is up).

## 9. Terminate an instance and verify replacement

```bash
INSTANCE=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)
aws ec2 terminate-instances --instance-ids "$INSTANCE"

watch -n 10 "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState,HealthStatus]' --output table"
```

Expected: the ASG notices the instance is gone, launches a replacement in a few minutes, and the group returns to its desired count with all targets healthy.

## 10. Availability during scaling

In one terminal, run a continuous probe:

```bash
while true; do
  curl -s -o /dev/null -w "%{time_starttransfer}s HTTP %{http_code}\n" --max-time 3 "http://$NLB" || echo "FAILED"
  sleep 1
done
```

In another, trigger scale-out (step 5) and scale-in (stop the load and wait; scale-in takes about 15+ minutes).

Expected:
- **Scale-out / scale-in**: no failures. New instances only receive traffic once healthy; removed instances are drained for 60 s first.
- **Abrupt termination (step 9)**: a few failed or slow requests are possible for up to roughly 30 s (interval 10 s × 3 failed checks), because the NLB only stops sending to the dead instance after it fails health checks. The healthy instance keeps serving. Shorten the window with a lower interval/threshold if needed.

## Cleanup

```bash
pkill stress-ng        # on the instance, if still running
terraform destroy
```
