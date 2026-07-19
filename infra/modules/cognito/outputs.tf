output "user_pool_id" {
  value       = aws_cognito_user_pool.this.id
  description = "User pool ID"
}

output "user_pool_arn" {
  value       = aws_cognito_user_pool.this.arn
  description = "User pool ARN"
}

output "app_client_id" {
  value = aws_cognito_user_pool_client.this.id
}