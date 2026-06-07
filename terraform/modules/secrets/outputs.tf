output "database_url_secret_arn" {
  description = "ARN of the DATABASE_URL secret."
  value       = aws_secretsmanager_secret.database_url.arn
}

output "anthropic_api_key_secret_arn" {
  description = "ARN of the Anthropic API key secret (null if not created)."
  value       = var.create_anthropic_key ? aws_secretsmanager_secret.anthropic_api_key[0].arn : null
}

output "secret_arns" {
  description = "All application secret ARNs (for the agent IAM policy)."
  value = compact([
    aws_secretsmanager_secret.database_url.arn,
    var.create_anthropic_key ? aws_secretsmanager_secret.anthropic_api_key[0].arn : "",
  ])
}
