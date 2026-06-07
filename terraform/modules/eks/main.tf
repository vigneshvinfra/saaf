# EKS module — control plane + system node group, following the established
# pattern: EKS Pod Identity (not legacy IRSA annotations), KMS-encrypted control
# plane logs + secrets, private API endpoint. The small managed node group hosts
# system addons + Karpenter; Karpenter then provisions the workload nodes.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# KMS key for the control-plane CloudWatch log group.
resource "aws_kms_key" "logs" {
  description             = "EKS control-plane logs (${var.cluster_name})"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRoot"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${var.cluster_name}/cluster"
          }
        }
      },
    ]
  })
}

# IAM role for the EBS CSI driver (Pod Identity).
resource "aws_iam_role" "ebs_csi" {
  name_prefix          = "${var.cluster_name}-ebs-csi-"
  permissions_boundary = var.permissions_boundary
  tags                 = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = var.endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  enable_irsa         = true
  authentication_mode = "API"

  enable_cluster_creator_admin_permissions = true

  iam_role_permissions_boundary = var.permissions_boundary

  # KMS-encrypt Kubernetes secrets at rest (module creates the key).
  create_kms_key = true
  cluster_encryption_config = {
    resources = ["secrets"]
  }

  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = var.log_retention_days
  cloudwatch_log_group_kms_key_id        = aws_kms_key.logs.arn
  cluster_enabled_log_types              = var.enabled_log_types

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
    metrics-server         = {} # required for the CPU HPA
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  # Node SG tagged for Karpenter discovery.
  node_security_group_tags = merge(var.tags, {
    "karpenter.sh/discovery" = var.cluster_name
  })

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.system_node_group.instance_types
      capacity_type  = var.system_node_group.capacity_type
      min_size       = var.system_node_group.min_size
      max_size       = var.system_node_group.max_size
      desired_size   = var.system_node_group.desired_size

      labels = { "saaf.io/node-role" = "system" }
    }
  }

  tags = var.tags
}

# Tag private subnets so Karpenter's EC2NodeClass can discover them by tag.
resource "aws_ec2_tag" "karpenter_subnets" {
  # Key by index: subnet ids come from the VPC created in this same apply, so
  # they're unknown at plan time and can't be for_each keys. The subnet count
  # (az_count) is statically known, which is all the for expression needs.
  for_each    = { for idx, id in var.private_subnet_ids : idx => id }
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# Grant extra principals (CI deploy role, platform team) cluster admin.
resource "aws_eks_access_entry" "admin" {
  for_each      = toset(var.admin_principal_arns)
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each      = toset(var.admin_principal_arns)
  cluster_name  = module.eks.cluster_name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
