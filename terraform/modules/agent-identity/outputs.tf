output "role_arn" {
  description = "IAM role ARN bound to the agent ServiceAccount via Pod Identity."
  value       = aws_iam_role.agent.arn
}

output "role_name" {
  description = "IAM role name."
  value       = aws_iam_role.agent.name
}
