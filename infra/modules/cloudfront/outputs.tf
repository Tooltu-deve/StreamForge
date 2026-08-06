output "domain" {
  value = aws_cloudfront_distribution.this.domain_name
}
output "cf_public_key_id" {
  value = aws_cloudfront_public_key.signing.id
}
