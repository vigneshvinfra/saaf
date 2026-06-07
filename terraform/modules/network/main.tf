# Network module — VPC + subnets + NAT + the VPC endpoints that keep the
# agent's AWS/Bedrock traffic on the AWS backbone (no internet egress for the
# sensitive paths). Wraps the well-maintained terraform-aws-modules/vpc.

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /24 per subnet, mirroring the established layout:
  #   private 10.x.1-3   nodes (NAT egress)
  #   intra   10.x.51-53 control-plane ENIs + interface endpoints (no egress)
  #   public  10.x.101-3 load balancers
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 1)]
  intra_subnets   = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 51)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 101)]

  # Interface endpoints that the agent + platform need. Gateway endpoints
  # (S3, DynamoDB) are handled separately (free, route-table based).
  interface_endpoints = toset(concat([
    "ecr.api",
    "ecr.dkr",
    "secretsmanager",
    "logs",
    "monitoring",
    "sts",
    "kms",
    "email-smtp", # SES outbound (borrower email)
    ], var.enable_bedrock_endpoint ? [
    "bedrock-runtime",
  ] : []))
}

# Not every interface-endpoint service is offered in every AZ (e.g. SES
# email-smtp). Look up each service's supported AZs so we only place its
# endpoint in subnets that can actually host it.
data "aws_vpc_endpoint_service" "interface" {
  for_each = local.interface_endpoints

  service_name = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  service_type = "Interface"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  intra_subnets   = local.intra_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Subnet discovery tags for the AWS Load Balancer Controller.
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }

  # VPC flow logs -> CloudWatch (network forensics / audit). KMS-encrypted when
  # a key is supplied by the environment.
  enable_flow_log                                 = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_flow_logs
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_logs_retention_days
  flow_log_cloudwatch_log_group_kms_key_id        = var.kms_key_arn

  tags = var.tags
}

# ----- VPC endpoints --------------------------------------------------------

# SG for the interface endpoints: allow 443 from inside the VPC only.
resource "aws_security_group" "endpoints" {
  name        = "${var.name}-vpce"
  description = "Allow HTTPS from within the VPC to interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# Gateway endpoints — S3 (borrower docs + audit) and DynamoDB (idempotency).
# Route-table based, free, and keep this traffic entirely off the internet.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(module.vpc.private_route_table_ids, module.vpc.intra_route_table_ids)
  tags              = merge(var.tags, { Name = "${var.name}-s3" })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(module.vpc.private_route_table_ids, module.vpc.intra_route_table_ids)
  tags              = merge(var.tags, { Name = "${var.name}-dynamodb" })
}

# Interface endpoints — placed in the intra subnets, private DNS enabled so the
# AWS SDKs resolve to them transparently.
resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type = "Interface"

  # Only the intra subnets whose AZ is in the service's supported set. Skips
  # AZs where the service isn't offered (e.g. email-smtp), which otherwise
  # fails CreateVpcEndpoint with InvalidParameter.
  subnet_ids = [
    for az, subnet_id in zipmap(local.azs, module.vpc.intra_subnets) :
    subnet_id
    if contains(data.aws_vpc_endpoint_service.interface[each.key].availability_zones, az)
  ]

  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name}-${each.value}" })
}
