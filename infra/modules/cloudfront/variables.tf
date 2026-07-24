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
