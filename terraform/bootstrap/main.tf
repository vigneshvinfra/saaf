# ---------------------------------------------------------------------------
# Remote state bootstrap
#
# Terraform config that uses a *local* backend, because it CREATES the S3 bucket + DynamoDB table
# every other environment uses as its remote backend. Apply this once per AWS account, commit the resulting
# bucket/table names into each environment's backend.tf, then never touch it.
#
#   cd terraform/bootstrap && terraform init && terraform apply
#
# Security posture (financial services):
#   - State holds secrets and ARNs -> bucket is KMS-encrypted, versioned, and
#     fully public-access-blocked.
#   - DynamoDB table provides state locking so two CI runs can't race.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "local" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "underwriting-agent"
      Component = "tf-remote-state"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.name_prefix}-tfstate-${data.aws_caller_identity.current.account_id}"
  table_name  = "${var.name_prefix}-tfstate-locks"
}

# KMS key dedicated to encrypting the state bucket.
resource "aws_kms_key" "state" {
  description             = "Encrypts the Terraform remote state bucket"
  deletion_window_in_days = 14
  enable_key_rotation     = true
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.name_prefix}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # State is precious — never let `terraform destroy` of this config nuke it.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Deny any non-TLS access to the state bucket.
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.state.arn,
        "${aws_s3_bucket.state.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

resource "aws_dynamodb_table" "locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }
}
