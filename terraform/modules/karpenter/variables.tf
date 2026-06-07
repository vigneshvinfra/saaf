variable "cluster_name" {
  description = "EKS cluster name Karpenter manages nodes for."
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
