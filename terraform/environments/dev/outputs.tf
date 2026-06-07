# Surface the stack outputs so operators can wire the Helm values after apply.
output "stack" {
  description = "All stack outputs (cluster, data stores, identities, secret ARNs)."
  value       = module.stack
}
