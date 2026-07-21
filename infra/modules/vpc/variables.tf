variable "vpc_cidr" {
  description = "Cidr block for VPC"
  type        = string
}


variable "name_prefix" {
  description = "Name prefix for the app"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "public_subnets" {
  description = "Map of AZ name => public subnet CIDR"
  type        = map(string)
}

variable "private_subnets" {
  description = "Map of AZ name => private subnet CIDR"
  type        = map(string)
}

variable "flow_log_retention_days" {
  description = "Retention days for Vpc Flow Logs"
  type        = number
  default     = 3
}