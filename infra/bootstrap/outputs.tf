output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "kms_key_arn" {
  value = aws_kms_key.terraform_state.arn
}

output "region" {
  value = var.region
}