variable "region" {
  type    = string
  default = "us-east-1"
}

variable "admin_principal_arns" {
  description = "Principals granted EKS cluster admin (CI deploy role, platform team)."
  type        = list(string)
  default     = []
}

variable "alarm_email" {
  description = "Email subscribed to CloudWatch alerts."
  type        = string
  default     = null
}
