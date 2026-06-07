# Karpenter module — AWS-side wiring only (IAM controller role via Pod Identity,
# node IAM role + instance profile, and the spot-interruption SQS queue Karpenter
# drains to gracefully cordon/drain reclaimed nodes).
#
# The Karpenter controller (Helm) and the NodePool/EC2NodeClass CRs are
# delivered via GitOps — see deploy/platform/. This split keeps Terraform
# validate-clean with only the AWS provider and matches the house pattern of
# not running Helm from Terraform.

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.31"

  cluster_name = var.cluster_name

  # Use EKS Pod Identity for the controller (no IRSA annotations).
  enable_pod_identity             = true
  create_pod_identity_association = true

  # Karpenter nodes assume this role; also create the access entry so the
  # nodes can join the cluster.
  node_iam_role_use_name_prefix      = true
  create_node_iam_role               = true
  create_access_entry                = true
  iam_role_permissions_boundary_arn  = var.permissions_boundary
  node_iam_role_permissions_boundary = var.permissions_boundary

  tags = var.tags
}
