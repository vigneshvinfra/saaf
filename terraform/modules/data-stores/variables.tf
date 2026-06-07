variable "name" {
  description = "Resource name prefix (e.g. saaf-uw-prod)."
  type        = string
}

variable "environment" {
  description = "Environment name (dev|staging|prod)."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the RDS instance + its security group."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets for the DB subnet group."
  type        = list(string)
}

variable "db_allowed_security_group_ids" {
  description = "Security groups allowed to reach Postgres on 5432 (the EKS node SG)."
  type        = list(string)
  default     = []
}

variable "db" {
  description = "RDS Postgres sizing + durability settings."
  type = object({
    engine_version        = optional(string, "16.4")
    instance_class        = optional(string, "db.t3.medium")
    allocated_storage     = optional(number, 50)
    max_allocated_storage = optional(number, 200)
    multi_az              = optional(bool, false)
    backup_retention_days = optional(number, 7)
    deletion_protection   = optional(bool, true)
  })
  default = {}
}

variable "audit_retention_years" {
  description = "S3 Object Lock retention for the LLM-call audit trail (compliance: 7 years)."
  type        = number
  default     = 7
}

variable "docs_noncurrent_days" {
  description = "Days to retain non-current versions of borrower docs before expiry."
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Allow non-empty S3 buckets to be destroyed (non-prod convenience). Never true with Object Lock."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
