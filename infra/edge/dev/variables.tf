variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "name_prefix" {
  type    = string
  default = "streamforge-dev"
}

variable "core_state_bucket" {
  type    = string
  default = "tooltu-streamforge-state"
}

variable "core_state_key" {
  type    = string
  default = "env/dev/terraform.tfstate"
}

variable "app_domain" {
  sensitive = true
  type      = string
}

variable "cf_cert_domain" {
  type = string
}

variable "origin_secret" {
  sensitive = true
  type      = string
}

variable "cf_public_key_pem" {
  description = "CloudFront signing public key PEM (from openssl, generated at deploy)"
  type        = string
}

