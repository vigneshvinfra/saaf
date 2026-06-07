# Platform add-ons — AWS-side IAM for the AWS Load Balancer Controller, wired to
# its ServiceAccount via EKS Pod Identity. The controller itself (Helm) and the
# other cluster components (Secrets Store CSI driver, kube-prometheus-stack) are
# installed via GitOps — see deploy/platform/. EBS CSI + metrics-server are EKS
# managed addons (see the eks module).

# Upstream IAM policy for the LB Controller, pinned to a release.
data "http" "lbc_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${var.lbc_policy_version}/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "lbc" {
  name_prefix = "${var.cluster_name}-lbc-"
  description = "AWS Load Balancer Controller (${var.cluster_name})"
  policy      = data.http.lbc_policy.response_body
  tags        = var.tags
}

resource "aws_iam_role" "lbc" {
  name_prefix          = "${var.cluster_name}-lbc-"
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

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# Bind the role to the controller's ServiceAccount (created by its Helm chart).
resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
}
