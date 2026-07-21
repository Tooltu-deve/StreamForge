output "repo_urls" {
  description = "Repositories urls"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repo_arns" {
  description = "Repositories arns"
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}