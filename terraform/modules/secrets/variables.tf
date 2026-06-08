variable "name" {
  description = "Resource name prefix (e.g. saaf-uw-prod)."
  type        = string
}

variable "environment" {
  description = "Environment name (dev|prod)."
  type        = string
}

variable "kms_key_arn" {
  description = "CMK used to encrypt these secrets."
  type        = string
}

variable "create_anthropic_key" {
  description = "Create the Anthropic API key secret (true for envs using the Anthropic provider; false for Bedrock/prod)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
