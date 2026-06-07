# These feed the Karpenter Helm values + EC2NodeClass delivered via GitOps.

output "controller_iam_role_arn" {
  description = "IAM role the Karpenter controller assumes (Pod Identity)."
  value       = module.karpenter.iam_role_arn
}

output "node_iam_role_name" {
  description = "IAM role name for Karpenter-provisioned nodes (-> EC2NodeClass)."
  value       = module.karpenter.node_iam_role_name
}

output "instance_profile_name" {
  description = "Instance profile for Karpenter nodes."
  value       = module.karpenter.instance_profile_name
}

output "interruption_queue_name" {
  description = "SQS queue Karpenter polls for spot-interruption / health events."
  value       = module.karpenter.queue_name
}

output "service_account" {
  description = "ServiceAccount name the controller runs as (for the Helm release)."
  value       = "karpenter"
}
