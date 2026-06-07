variable "name" {
  description = "Resource name prefix (e.g. saaf-uw-prod)."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "db_instance_id" {
  description = "RDS instance identifier to alarm on."
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB idempotency table to alarm on."
  type        = string
}

variable "alarm_email" {
  description = "Optional email subscribed to the alerts SNS topic."
  type        = string
  default     = null
}

variable "db_connection_alarm_threshold" {
  description = "DatabaseConnections alarm threshold."
  type        = number
  default     = 80
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
