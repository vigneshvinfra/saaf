output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Cluster security group ID (control-plane <-> nodes)."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Node security group ID (tagged for Karpenter discovery)."
  value       = module.eks.node_security_group_id
}
