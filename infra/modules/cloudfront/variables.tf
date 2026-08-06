variable "frontend_bucket_id" { type = string }
variable "frontend_bucket_arn" { type = string }
variable "frontend_bucket_domain" { type = string } # regional domain: <bucket>.s3.<region>.amazonaws.com
variable "alb_dns_name" { type = string }
variable "acm_cert_arn" { type = string }  # us-east-1
variable "aliases" { type = list(string) } # ["app.<domain>"]
variable "origin_secret" {
  type      = string
  sensitive = true
}

variable "transcoded_bucket_id" { type = string }
variable "transcoded_bucket_arn" { type = string }
variable "transcoded_bucket_domain" { type = string } # <bucket>.s3.<region>.amazonaws.com

variable "signing_public_key_pem" {
  description = "CloudFront signed-cookie public key (PEM). Public, not secret."
  type        = string
}
