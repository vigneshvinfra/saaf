output "ecr_repository_url" {
  description = "ECR repo URL for the agent image (-> chart image.repository)."
  value       = aws_ecr_repository.agent.repository_url
}

output "gha_ecr_push_role_arn" {
  description = "Role GitHub Actions assumes to push images."
  value       = aws_iam_role.gha_ecr_push.arn
}

output "gha_tf_plan_role_arn" {
  description = "Role GitHub Actions assumes for terraform plan."
  value       = aws_iam_role.gha_tf_plan.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN."
  value       = aws_iam_openid_connect_provider.github.arn
}
