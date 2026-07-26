output "cloudfront_domain" {
  description = "CloudFront distribution domain (the single public entry point)"
  value       = module.cloudfront.domain
}
