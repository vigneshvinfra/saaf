# Account-wide, environment-independent resources:
#   - ECR repository for the agent image (immutable tags, scan on push, KMS)
#   - GitHub Actions OIDC provider + CI roles (no long-lived AWS keys anywhere)

data "aws_caller_identity" "current" {}

# ----- ECR ------------------------------------------------------------------
resource "aws_kms_key" "ecr" {
  description             = "ECR image encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 14
}

resource "aws_ecr_repository" "agent" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "IMMUTABLE" # tags are git SHAs — never overwrite

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
}

# Keep the last 30 images; expire untagged after 7 days.
resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged after 7 days"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 30 tagged images"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }
        action       = { type = "expire" }
      },
    ]
  })
}

# ----- GitHub Actions OIDC --------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprints (AWS no longer validates these for IAM-managed
  # GitHub OIDC, but the field is still required).
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_policy_document" "gha_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

# CI role 1 — push images to ECR.
resource "aws_iam_role" "gha_ecr_push" {
  name               = "gha-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.gha_trust.json
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "GetAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid    = "PushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.agent.arn]
  }
}

resource "aws_iam_role_policy" "gha_ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.gha_ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# CI role 2 — terraform plan on PRs (read-only + state access). Apply is done by
# a separately-provisioned, more privileged role / human-gated pipeline.
resource "aws_iam_role" "gha_tf_plan" {
  name               = "gha-tf-plan"
  assume_role_policy = data.aws_iam_policy_document.gha_trust.json
}

resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.gha_tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "tf_state_access" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::saaf-uw-tfstate-${data.aws_caller_identity.current.account_id}", "arn:aws:s3:::saaf-uw-tfstate-${data.aws_caller_identity.current.account_id}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/saaf-uw-tfstate-locks"]
  }
}

resource "aws_iam_role_policy" "gha_tf_state" {
  name   = "tf-state-access"
  role   = aws_iam_role.gha_tf_plan.id
  policy = data.aws_iam_policy_document.tf_state_access.json
}
