# Idempotency table — the agent's store layer keys each (loan_id, item_id) write
# here with a conditional put, so a retried item never produces a duplicate
# outbound email or task record (compliance: idempotent processing). TTL prunes
# old keys; PITR + KMS satisfy durability + encryption-at-rest.

resource "aws_dynamodb_table" "idempotency" {
  name         = "${var.name}-idempotency"
  billing_mode = "PAY_PER_REQUEST" # bursty + low volume -> pay per request
  hash_key     = "idempotency_key"

  attribute {
    name = "idempotency_key"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.data.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = var.tags
}
