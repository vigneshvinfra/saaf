output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA cert for the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "Cluster security group ID (control-plane <-> nodes)."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Node security group ID (tagged for Karpenter discovery)."
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "IRSA OIDC provider ARN."
  value       = module.eks.oidc_provider_arn
}

output "cluster_version" {
  description = "Kubernetes version running."
  value       = module.eks.cluster_version
}
