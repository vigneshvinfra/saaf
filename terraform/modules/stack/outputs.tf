# Outputs consumed by operators wiring up the Helm values / platform components
# after apply. (Helm/ArgoCD are out-of-band; these provide the values to paste.)

output "cluster_name" {
  value = module.eks.cluster_name
}
output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
output "region" {
  value = data.aws_region.current.name
}

# Data plane
output "db_endpoint" {
  value = module.data_stores.db_endpoint
}
output "db_master_secret_arn" {
  value = module.data_stores.db_master_secret_arn
}
output "docs_bucket" {
  value = module.data_stores.docs_bucket
}
output "audit_bucket" {
  value = module.data_stores.audit_bucket
}
output "idempotency_table" {
  value = module.data_stores.idempotency_table_name
}

# Secrets -> chart values-<env>.yaml (secrets.objects[*].arn)
output "database_url_secret_arn" {
  value = module.secrets.database_url_secret_arn
}
output "anthropic_api_key_secret_arn" {
  value = module.secrets.anthropic_api_key_secret_arn
}

# Identities -> Helm values for the relevant components
output "agent_role_arn" {
  value = module.agent_identity.role_arn
}
output "lbc_role_arn" {
  value = module.platform_addons.lbc_role_arn
}
output "karpenter_controller_role_arn" {
  value = module.karpenter.controller_iam_role_arn
}
output "karpenter_node_role_name" {
  value = module.karpenter.node_iam_role_name
}
output "karpenter_interruption_queue" {
  value = module.karpenter.interruption_queue_name
}

# Ops
output "alerts_sns_topic_arn" {
  value = module.observability.sns_topic_arn
}
output "bastion_ssm_command" {
  value = var.create_bastion ? module.bastion[0].ssm_command : null
}
