output "table_name" {
  description = "Table name"
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "Table ARN"
  value       = aws_dynamodb_table.this.arn
}

output "gsi1_name" {
  description = "GSI1 name"
  value       = local.gsi1_name
}