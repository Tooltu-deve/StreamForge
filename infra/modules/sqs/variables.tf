variable "name_prefix" {
  type = string
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 900
}

variable "max_receive_count" {
  type    = number
  default = 3
}

variable "raw_bucket_arn" {
  type = string
}