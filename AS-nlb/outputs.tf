# -----------------------------------------------------------------------------
# outputs.tf - Values printed after `terraform apply` (and by `terraform output`)
# -----------------------------------------------------------------------------

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer."
  value       = aws_lb.nlb.dns_name
}

output "nlb_url" {
  description = "URL to open in a browser or curl."
  value       = "http://${aws_lb.nlb.dns_name}:${var.app_port}"
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs keyed by Availability Zone."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnet_ids" {
  description = "Private subnet IDs keyed by Availability Zone."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT Gateway(s) (outbound source IPs of the instances)."
  value       = { for az, e in aws_eip.nat : az => e.public_ip }
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.web.name
}

output "launch_template_id" {
  description = "ID of the EC2 Launch Template."
  value       = aws_launch_template.web.id
}

output "target_group_arn" {
  description = "ARN of the NLB target group."
  value       = aws_lb_target_group.web.arn
}

output "ami_id" {
  description = "Ubuntu 24.04 AMI used by the Launch Template."
  value       = local.ami_id
}

output "check_target_health_command" {
  description = "AWS CLI command to see target health."
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.web.arn} --region ${var.aws_region} --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table"
}

output "list_instances_command" {
  description = "AWS CLI command to list the ASG instances."
  value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.web.name} --region ${var.aws_region} --query 'AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]' --output table"
}
