# The full per-environment stack. Each environment root (dev/staging/prod) calls
# this module with env-specific sizing/toggles, so the composition lives in one
# place and the env roots stay tiny.

variable "name" {
  description = "Name prefix for everything in this env (e.g. saaf-uw-prod)."
  type        = string
}

variable "environment" {
  description = "dev | staging | prod."
  type        = string
}

# ----- network -----
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "az_count" {
  type    = number
  default = 3
}
variable "single_nat_gateway" {
  type    = bool
  default = true
}

# ----- eks -----
variable "kubernetes_version" {
  type    = string
  default = "1.32"
}
variable "endpoint_public_access" {
  type    = bool
  default = false
}
variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = []
}
variable "system_node_group" {
  type = object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    capacity_type  = optional(string, "ON_DEMAND")
  })
  default = {
    instance_types = ["t3.large"]
    min_size       = 2
    max_size       = 4
    desired_size   = 2
  }
}
variable "admin_principal_arns" {
  description = "Principals granted cluster admin (CI deploy role, platform team)."
  type        = list(string)
  default     = []
}

# ----- data -----
variable "db" {
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
  type    = number
  default = 7
}
variable "force_destroy" {
  type    = bool
  default = false
}

# ----- LLM / app -----
variable "llm_provider" {
  description = "anthropic | bedrock — decides Bedrock endpoint + IAM + secret creation."
  type        = string
  default     = "anthropic"
}
variable "bedrock_model_ids" {
  description = "Bedrock model IDs the agent may invoke (used to build IAM ARNs)."
  type        = list(string)
  default     = ["anthropic.claude-sonnet-4-6-v1:0"]
}
variable "ses_from_address" {
  type    = string
  default = "loans@saaffinance.com"
}
variable "agent_namespace" {
  description = "Namespace the agent runs in (matches the ArgoCD destination)."
  type        = string
}

# ----- ops -----
variable "alarm_email" {
  type    = string
  default = null
}
variable "create_bastion" {
  type    = bool
  default = true
}
variable "permissions_boundary" {
  type    = string
  default = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
