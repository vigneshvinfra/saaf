# Application secrets the agent consumes via the Secrets Store CSI driver.
#
# Pattern (matches the house style): Terraform creates the secret CONTAINER with
# a placeholder value, then ignores the value forever. The real value is written
# out-of-band (CI on first deploy, or a rotation Lambda), so Terraform never
# stores or drifts the actual secret.
#
#   aws secretsmanager put-secret-value --secret-id <name> --secret-string <value>
#
# Rotation (compliance: quarterly minimum):
#   - DATABASE_URL : the RDS master password is auto-rotated by RDS; a small
#     rotation Lambda keeps this URL in sync (out of scope to implement here;
#     see docs/COMPLIANCE.md). The 90-day reminder is encoded below.
#   - ANTHROPIC_API_KEY : rotated via the provider console + put-secret-value.
#
# Note: the agent reads DATABASE_URL as a single connection string (we don't
# modify the agent), which is why we keep a full-URL secret rather than handing
# it the raw RDS-managed credential JSON.

# ----- DATABASE_URL ---------------------------------------------------------
resource "aws_secretsmanager_secret" "database_url" {
  name                    = "${var.name}/database-url"
  description             = "Full Postgres connection string consumed by the agent as DATABASE_URL"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.environment == "prod" ? 30 : 7
  tags                    = merge(var.tags, { RotateEveryDays = "90" })
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql+psycopg://REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ----- ANTHROPIC_API_KEY (non-Bedrock envs) ---------------------------------
resource "aws_secretsmanager_secret" "anthropic_api_key" {
  count                   = var.create_anthropic_key ? 1 : 0
  name                    = "${var.name}/anthropic-api-key"
  description             = "Anthropic API key (no-training agreement); consumed as ANTHROPIC_API_KEY"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.environment == "prod" ? 30 : 7
  tags                    = merge(var.tags, { RotateEveryDays = "90" })
}

resource "aws_secretsmanager_secret_version" "anthropic_api_key" {
  count         = var.create_anthropic_key ? 1 : 0
  secret_id     = aws_secretsmanager_secret.anthropic_api_key[0].id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
