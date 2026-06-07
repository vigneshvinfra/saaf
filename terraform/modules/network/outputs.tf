output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnets — EKS nodes live here (NAT egress)."
  value       = module.vpc.private_subnets
}

output "intra_subnet_ids" {
  description = "Intra subnets — control-plane ENIs + interface endpoints (no egress)."
  value       = module.vpc.intra_subnets
}

output "public_subnet_ids" {
  description = "Public subnets — internet-facing load balancers."
  value       = module.vpc.public_subnets
}

output "endpoint_security_group_id" {
  description = "SG attached to the interface VPC endpoints."
  value       = aws_security_group.endpoints.id
}

output "azs" {
  description = "Availability zones the VPC spans."
  value       = local.azs
}
