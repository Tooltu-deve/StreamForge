variable "name_prefix" {
  description = "Name prefix"
  type        = string
}

variable "raw_expiration_days" {
  description = "Expiration days for raw bucket"
  type        = number
  default     = 7
}

variable "app_domain" {
  type = string
}