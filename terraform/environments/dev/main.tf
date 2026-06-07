# dev — smallest footprint, Anthropic API, spot system nodes, disposable data.
module "stack" {
  source = "../../modules/stack"

  name        = "saaf-uw-dev"
  environment = "dev"

  # Network — 2 AZs, single NAT (cost).
  vpc_cidr           = "10.10.0.0/16"
  az_count           = 2
  single_nat_gateway = true

  # EKS — small spot system pool.
  kubernetes_version = "1.32"
  system_node_group = {
    instance_types = ["t3.large"]
    capacity_type  = "SPOT"
    min_size       = 1
    max_size       = 3
    desired_size   = 2
  }
  admin_principal_arns = var.admin_principal_arns

  # Data — disposable.
  db = {
    instance_class        = "db.t3.medium"
    allocated_storage     = 20
    multi_az              = false
    backup_retention_days = 1
    deletion_protection   = false
  }
  force_destroy = true

  # LLM — Anthropic API (key in Secrets Manager).
  llm_provider    = "anthropic"
  agent_namespace = "uw-dev"

  alarm_email = var.alarm_email
  tags        = { CostCenter = "underwriting-rnd" }
}
