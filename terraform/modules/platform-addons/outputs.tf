output "lbc_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller (Pod Identity)."
  value       = aws_iam_role.lbc.arn
}

output "lbc_service_account" {
  description = "ServiceAccount the LB Controller Helm release must use."
  value       = "aws-load-balancer-controller"
}
