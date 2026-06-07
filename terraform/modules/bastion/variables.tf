variable "name" {
  description = "Resource name prefix."
  type        = string
}

variable "vpc_id" {
  description = "VPC the bastion lives in."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet (with NAT egress for SSM) for the bastion."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster the bastion administers."
  type        = string
}

variable "cluster_security_group_id" {
  description = "Cluster SG — a rule is added allowing 443 from the bastion."
  type        = string
}

variable "instance_type" {
  description = "Bastion instance type."
  type        = string
  default     = "t3.micro"
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
