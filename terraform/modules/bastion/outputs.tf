output "instance_id" {
  description = "Bastion EC2 instance ID."
  value       = aws_instance.bastion.id
}

output "ssm_command" {
  description = "Open a shell on the bastion via SSM."
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${data.aws_region.current.name}"
}
