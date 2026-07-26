output "controller_role_arn" {
  description = "IRSA role ARN for the LB controller"
  value       = aws_iam_role.this.arn
}

output "helm_release_name" {
  description = "Helm release name"
  value       = helm_release.this.name
}
