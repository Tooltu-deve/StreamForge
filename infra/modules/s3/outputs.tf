output "bucket_names" {
  description = "Map of logical name => bucket name"
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}

output "bucket_arns" {
  description = "Map of logical name => bucket ARN"
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}
