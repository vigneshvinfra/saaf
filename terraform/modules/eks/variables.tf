variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.32"
}

variable "vpc_id" {
  description = "VPC the cluster lives in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets for worker nodes."
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "Intra subnets for the control-plane ENIs."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the EKS API endpoint publicly. Keep false for prod."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public endpoint (only used if public access is on)."
  type        = list(string)
  default     = []
}

variable "enabled_log_types" {
  description = "Control-plane log types shipped to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "Retention for the control-plane log group."
  type        = number
  default     = 90
}

variable "system_node_group" {
  description = "Sizing for the small managed node group that hosts system addons + Karpenter."
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

variable "permissions_boundary" {
  description = "IAM permissions boundary ARN for cluster-created roles, or null."
  type        = string
  default     = null
}

variable "admin_principal_arns" {
  description = "IAM principal ARNs granted cluster-admin via EKS access entries (e.g. CI deploy role, platform team)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
