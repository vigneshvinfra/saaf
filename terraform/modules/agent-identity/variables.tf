variable "name" {
  description = "Resource name prefix (e.g. saaf-uw-prod)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster the agent runs on."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the agent runs in."
  type        = string
}

variable "service_account" {
  description = "Agent ServiceAccount name (must match the Helm chart)."
  type        = string
  default     = "underwriting-agent"
}

variable "docs_bucket_arn" {
  description = "Borrower documents bucket ARN (read)."
  type        = string
}

variable "audit_bucket_arn" {
  description = "Audit trail bucket ARN (write-only)."
  type        = string
}

variable "idempotency_table_arn" {
  description = "DynamoDB idempotency table ARN."
  type        = string
}

variable "secret_arns" {
  description = "Secrets Manager ARNs the agent reads (DATABASE_URL, API key, RDS master)."
  type        = list(string)
}

variable "kms_key_arns" {
  description = "KMS key ARNs the agent must use (data + audit keys)."
  type        = list(string)
}

variable "enable_bedrock" {
  description = "Grant Bedrock InvokeModel (prod LLM path)."
  type        = bool
  default     = false
}

variable "bedrock_model_arns" {
  description = "Bedrock foundation-model ARNs the agent may invoke."
  type        = list(string)
  default     = []
}

variable "ses_from_address" {
  description = "Verified SES sender; the agent may only send From this address."
  type        = string
}

variable "permissions_boundary" {
  description = "IAM permissions boundary ARN, or null."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
