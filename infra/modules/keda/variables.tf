variable "name_prefix" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}


variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "chart_version" {
  type = string
}

variable "queue_arn" {
  type = string
}