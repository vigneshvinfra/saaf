# Two CMKs: one for the live data plane (RDS, S3 docs, DynamoDB) and a separate
# one for the audit trail (different blast radius + key policy; audit data
# outlives everything else). Both rotate annually.

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "data" {
  description             = "${var.name} data plane (RDS / S3 docs / DynamoDB)"
  deletion_window_in_days = 14
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "data" {
  name          = "alias/${var.name}-data"
  target_key_id = aws_kms_key.data.key_id
}

resource "aws_kms_key" "audit" {
  description             = "${var.name} audit trail (7-year LLM-call records)"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "audit" {
  name          = "alias/${var.name}-audit"
  target_key_id = aws_kms_key.audit.key_id
}
