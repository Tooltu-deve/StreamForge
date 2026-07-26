output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "bucket_names" { value = module.s3.bucket_names }
output "table_name" { value = module.dynamodb.table_name }
output "user_pool_id" { value = module.cognito.user_pool_id }
output "app_client_id" { value = module.cognito.app_client_id }
output "ecr_repo_urls" { value = module.ecr.repo_urls }

output "cluster_ca_data" {
  description = "Base64 cluster CA (for kubeconfig / k8s provider)"
  value       = module.eks.cluster_ca_data
}

output "oidc_provider_url" {
  description = "EKS OIDC provider URL (for IRSA trust conditions)"
  value       = module.eks.oidc_provider_url
}

output "vpc_id" {
  description = "VPC id (for the ALB controller)"
  value       = module.vpc.vpc_id
}

output "raw_bucket_arn" {
  value = module.s3.bucket_arns["raw"]
}

output "frontend_bucket_arn" {
  description = "Frontend bucket ARN (consumed by the edge/CloudFront layer)"
  value       = module.s3.bucket_arns["frontend"]
}

output "table_arn" {
  value = module.dynamodb.table_arn
}
