data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  use_bedrock = var.llm_provider == "bedrock"

  # Bedrock foundation-model ARNs the agent may invoke (region-scoped, account-less).
  bedrock_model_arns = [
    for id in var.bedrock_model_ids :
    "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${id}"
  ]

  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = "underwriting-agent"
    ManagedBy   = "terraform"
  })
}

module "network" {
  source = "../network"

  name                    = var.name
  vpc_cidr                = var.vpc_cidr
  az_count                = var.az_count
  single_nat_gateway      = var.single_nat_gateway
  enable_bedrock_endpoint = local.use_bedrock
  tags                    = local.common_tags
}

module "eks" {
  source = "../eks"

  cluster_name                 = var.name
  kubernetes_version           = var.kubernetes_version
  vpc_id                       = module.network.vpc_id
  private_subnet_ids           = module.network.private_subnet_ids
  control_plane_subnet_ids     = module.network.intra_subnet_ids
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  system_node_group            = var.system_node_group
  admin_principal_arns         = var.admin_principal_arns
  permissions_boundary         = var.permissions_boundary
  tags                         = local.common_tags
}

module "karpenter" {
  source = "../karpenter"

  cluster_name         = module.eks.cluster_name
  permissions_boundary = var.permissions_boundary
  tags                 = local.common_tags
}

module "platform_addons" {
  source = "../platform-addons"

  cluster_name         = module.eks.cluster_name
  permissions_boundary = var.permissions_boundary
  tags                 = local.common_tags
}

module "data_stores" {
  source = "../data-stores"

  name                          = var.name
  environment                   = var.environment
  vpc_id                        = module.network.vpc_id
  private_subnet_ids            = module.network.private_subnet_ids
  db_allowed_security_group_ids = [module.eks.node_security_group_id]
  db                            = var.db
  audit_retention_years         = var.audit_retention_years
  force_destroy                 = var.force_destroy
  tags                          = local.common_tags
}

module "secrets" {
  source = "../secrets"

  name                 = var.name
  environment          = var.environment
  kms_key_arn          = module.data_stores.data_kms_key_arn
  create_anthropic_key = !local.use_bedrock
  tags                 = local.common_tags
}

module "agent_identity" {
  source = "../agent-identity"

  name                  = var.name
  cluster_name          = module.eks.cluster_name
  namespace             = var.agent_namespace
  docs_bucket_arn       = module.data_stores.docs_bucket_arn
  audit_bucket_arn      = module.data_stores.audit_bucket_arn
  idempotency_table_arn = module.data_stores.idempotency_table_arn
  secret_arns           = concat(module.secrets.secret_arns, [module.data_stores.db_master_secret_arn])
  kms_key_arns          = [module.data_stores.data_kms_key_arn, module.data_stores.audit_kms_key_arn]
  enable_bedrock        = local.use_bedrock
  bedrock_model_arns    = local.bedrock_model_arns
  ses_from_address      = var.ses_from_address
  permissions_boundary  = var.permissions_boundary
  tags                  = local.common_tags
}

module "observability" {
  source = "../observability"

  name                = var.name
  environment         = var.environment
  db_instance_id      = "${var.name}-pg"
  dynamodb_table_name = module.data_stores.idempotency_table_name
  alarm_email         = var.alarm_email
  tags                = local.common_tags
}

module "bastion" {
  source = "../bastion"
  count  = var.create_bastion ? 1 : 0

  name                      = var.name
  vpc_id                    = module.network.vpc_id
  subnet_id                 = module.network.private_subnet_ids[0]
  cluster_name              = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_security_group_id
  permissions_boundary      = var.permissions_boundary
  tags                      = local.common_tags
}
