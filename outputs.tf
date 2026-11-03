output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.web.dns_name
}

output "alb_url" {
  description = "Open this URL in a browser to test."
  value       = "http://${aws_lb.web.dns_name}"
}

output "target_group_arn" {
  description = "Target group ARN (use with aws elbv2 describe-target-health)."
  value       = aws_lb_target_group.web.arn
}

output "autoscaling_group_name" {
  description = "Auto Scaling group name."
  value       = aws_autoscaling_group.web.name
}

output "launch_template_id" {
  description = "Launch template ID."
  value       = aws_launch_template.web.id
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_public_ips" {
  description = "Public IPs the instances use for outbound internet traffic."
  value       = aws_eip.nat[*].public_ip
}

output "describe_asg_command" {
  description = "Shows capacity, instances and their health."
  value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.web.name} --region ${var.aws_region} --query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Instances:Instances[].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]}'"
}

output "check_target_health_command" {
  description = "Shows which instances the ALB considers healthy."
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.web.arn} --region ${var.aws_region} --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table"
}
