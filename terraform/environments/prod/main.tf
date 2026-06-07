# prod — HA across 3 AZs, per-AZ NAT, Bedrock via PrivateLink (no internet
# egress for LLM calls), multi-AZ RDS, deletion protection. Targets 99.9%.
module "stack" {
  source = "../../modules/stack"

  name        = "saaf-uw-prod"
  environment = "prod"

  # Network — 3 AZs, NAT per AZ (no SPOF).
  vpc_cidr           = "10.30.0.0/16"
  az_count           = 3
  single_nat_gateway = false

  kubernetes_version = "1.32"
  system_node_group = {
    instance_types = ["m6i.large"]
    capacity_type  = "ON_DEMAND"
    min_size       = 3
    max_size       = 6
    desired_size   = 3
  }
  admin_principal_arns = var.admin_principal_arns

  # Data — HA + durable. Multi-AZ + PITR meet RPO 1h / RTO 30m.
  db = {
    engine_version        = "16.4"
    instance_class        = "db.r6g.large"
    allocated_storage     = 100
    max_allocated_storage = 500
    multi_az              = true
    backup_retention_days = 14
    deletion_protection   = true
  }
  audit_retention_years = 7
  force_destroy         = false

  # LLM — Bedrock via the PrivateLink endpoint (IAM-auditable, no-training).
  llm_provider      = "bedrock"
  bedrock_model_ids = ["anthropic.claude-sonnet-4-6-v1:0"]
  agent_namespace   = "uw-prod"

  alarm_email = var.alarm_email
  tags        = { CostCenter = "underwriting-platform" }
}
