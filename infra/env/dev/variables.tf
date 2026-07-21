variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "name_prefix" {
  type    = string
  default = "streamforge-dev"
}
variable "cluster_name" {
  type    = string
  default = "streamforge-dev"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "public_subnets" {
  type = map(string)
} # AZ => CIDR

variable "private_subnets" {
  type = map(string)
}

variable "public_access_cidrs" {
  type = list(string)
} # IP operator

variable "cluster_admin_principal_arns" {
  type = list(string)
} # operator + CI role

variable "ecr_services" {
  type = list(string)
}
