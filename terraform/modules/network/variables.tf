variable "name" {
  description = "Name prefix for the VPC and associated resources (e.g. saaf-uw-prod)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to span (3 for prod HA)."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "true = one NAT GW (cheap, non-prod); false = one per AZ (HA, prod)."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Ship VPC flow logs to CloudWatch (audit/forensics)."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retention for the VPC flow log group."
  type        = number
  default     = 90
}

variable "enable_bedrock_endpoint" {
  description = "Create the Bedrock runtime interface endpoint (prod LLM path via PrivateLink)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
