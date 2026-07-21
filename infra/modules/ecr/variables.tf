variable "name_prefix" {
  description = "Name prefix"
  type        = string
}

variable "services" {
  description = "List of services"
  type        = list(string)
}

variable "image_count" {
  description = "Number of images to keep"
  type        = number
  default     = 3
}