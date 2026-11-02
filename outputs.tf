output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer."
  value       = aws_lb.nlb.dns_name
}

output "nlb_url" {
  description = "Open this URL in a browser to test."
  value       = "http://${aws_lb.nlb.dns_name}:${var.listener_port}"
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer."
  value       = aws_lb.nlb.arn
}

output "target_group_arn" {
  description = "ARN of the target group (use it with aws elbv2 describe-target-health)."
  value       = aws_lb_target_group.nginx.arn
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

output "instance_ids" {
  description = "EC2 instance IDs by name."
  value       = { for name, instance in aws_instance.web : name => instance.id }
}

output "instance_public_ips" {
  description = "Public IPs by name (instances only accept traffic from the NLB, these are for reference)."
  value       = { for name, instance in aws_instance.web : name => instance.public_ip }
}

output "check_target_health_command" {
  description = "Command to check target health."
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.nginx.arn} --region ${var.aws_region} --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table"
}
