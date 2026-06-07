output "state_bucket" {
  description = "Name of the S3 bucket holding remote state. Paste into each env's backend.tf."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "DynamoDB table used for state locking. Paste into each env's backend.tf."
  value       = aws_dynamodb_table.locks.name
}

output "kms_key_arn" {
  description = "KMS key encrypting the state bucket."
  value       = aws_kms_key.state.arn
}
