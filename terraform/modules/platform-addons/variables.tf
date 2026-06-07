variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "lbc_policy_version" {
  description = "AWS Load Balancer Controller release whose IAM policy to fetch."
  type        = string
  default     = "v2.14.1"
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
