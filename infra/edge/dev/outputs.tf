output "cloudfront_domain" {
  description = "CloudFront distribution domain (the single public entry point)"
  value       = module.cloudfront.domain
}

output "cf_public_key_id" {
  value = module.cloudfront.cf_public_key_id
}
