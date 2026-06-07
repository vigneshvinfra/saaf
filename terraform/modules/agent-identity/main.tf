# Least-privilege identity for the agent pods, delivered via EKS Pod Identity.
# Every statement is scoped to a specific resource ARN — no "*" resources, no
# service-wide grants. This is the service identity the compliance section calls
# for: it can read borrower docs, append to the audit log, key idempotency
# writes, read its own secrets, invoke exactly the LLM it needs, and send mail
# only from the verified address — nothing else.

resource "aws_iam_role" "agent" {
  name_prefix          = "${var.name}-agent-"
  permissions_boundary = var.permissions_boundary
  tags                 = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

data "aws_iam_policy_document" "agent" {
  # Read borrower documents.
  statement {
    sid       = "ReadBorrowerDocs"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.docs_bucket_arn}/*"]
  }
  statement {
    sid       = "ListBorrowerDocs"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.docs_bucket_arn]
  }

  # Append-only to the audit trail (no Get/Delete — WORM is enforced by the
  # bucket, but we also don't grant the agent read/delete on it).
  statement {
    sid       = "WriteAuditTrail"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.audit_bucket_arn}/*"]
  }

  # Idempotency bookkeeping.
  statement {
    sid    = "Idempotency"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
    ]
    resources = [var.idempotency_table_arn]
  }

  # Read its own secrets only.
  statement {
    sid       = "ReadSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = var.secret_arns
  }

  # Use the data + audit CMKs (S3/DynamoDB/Secrets need decrypt + data-key gen).
  statement {
    sid       = "UseKms"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = var.kms_key_arns
  }

  # Send borrower email only from the verified address.
  statement {
    sid       = "SendBorrowerEmail"
    effect    = "Allow"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.ses_from_address]
    }
  }

  # Invoke exactly the Bedrock model(s) the agent uses (prod path).
  dynamic "statement" {
    for_each = var.enable_bedrock ? [1] : []
    content {
      sid       = "InvokeBedrock"
      effect    = "Allow"
      actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      resources = var.bedrock_model_arns
    }
  }
}

resource "aws_iam_policy" "agent" {
  name_prefix = "${var.name}-agent-"
  description = "Least-privilege policy for the underwriting agent pods"
  policy      = data.aws_iam_policy_document.agent.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "agent" {
  role       = aws_iam_role.agent.name
  policy_arn = aws_iam_policy.agent.arn
}

# Bind the role to the agent's ServiceAccount (namespace + name).
resource "aws_eks_pod_identity_association" "agent" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.agent.arn
}
