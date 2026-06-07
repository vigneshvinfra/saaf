# staging — prod-shaped but smaller and cheaper. Anthropic API path so the
# secret-rotation/external-egress flow is exercised before prod.
module "stack" {
  source = "../../modules/stack"

  name        = "saaf-uw-staging"
  environment = "staging"

  # Network — 3 AZs, single NAT (staging tolerates the SPOF).
  vpc_cidr           = "10.20.0.0/16"
  az_count           = 3
  single_nat_gateway = true

  kubernetes_version = "1.32"
  system_node_group = {
    instance_types = ["t3.large"]
    capacity_type  = "ON_DEMAND"
    min_size       = 2
    max_size       = 4
    desired_size   = 2
  }
  admin_principal_arns = var.admin_principal_arns

  db = {
    instance_class        = "db.t3.medium"
    allocated_storage     = 50
    multi_az              = false
    backup_retention_days = 7
    deletion_protection   = true
  }
  force_destroy = false

  llm_provider    = "anthropic"
  agent_namespace = "uw-staging"

  alarm_email = var.alarm_email
  tags        = { CostCenter = "underwriting-platform" }
}
