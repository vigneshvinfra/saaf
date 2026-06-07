variable "region" {
  description = "AWS region for the remote state bucket + lock table."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for the state bucket and lock table names."
  type        = string
  default     = "saaf-uw"
}
