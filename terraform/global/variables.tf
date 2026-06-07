variable "region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI roles via OIDC, as 'org/repo'."
  type        = string
  default     = "your-org/saaf-underwriting-infra"
}

variable "ecr_repo_name" {
  description = "ECR repository name for the agent image."
  type        = string
  default     = "underwriting-agent"
}
