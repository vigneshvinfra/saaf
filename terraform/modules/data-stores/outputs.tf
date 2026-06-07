output "data_kms_key_arn" {
  description = "CMK for the live data plane (RDS / S3 docs / DynamoDB)."
  value       = aws_kms_key.data.arn
}

output "audit_kms_key_arn" {
  description = "CMK for the audit trail."
  value       = aws_kms_key.audit.arn
}

output "db_endpoint" {
  description = "RDS Postgres endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "RDS Postgres hostname."
  value       = aws_db_instance.this.address
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "db_master_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed (auto-rotating) master credentials."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "db_security_group_id" {
  description = "Security group fronting Postgres."
  value       = aws_security_group.db.id
}

output "docs_bucket" {
  description = "Borrower documents bucket name."
  value       = aws_s3_bucket.docs.id
}

output "docs_bucket_arn" {
  description = "Borrower documents bucket ARN."
  value       = aws_s3_bucket.docs.arn
}

output "audit_bucket" {
  description = "Audit trail bucket name."
  value       = aws_s3_bucket.audit.id
}

output "audit_bucket_arn" {
  description = "Audit trail bucket ARN."
  value       = aws_s3_bucket.audit.arn
}

output "idempotency_table_name" {
  description = "DynamoDB idempotency table name."
  value       = aws_dynamodb_table.idempotency.name
}

output "idempotency_table_arn" {
  description = "DynamoDB idempotency table ARN."
  value       = aws_dynamodb_table.idempotency.arn
}
