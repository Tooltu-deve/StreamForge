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

variable "lbc_chart_version" {
  description = "aws-load-balancer-controller chart version (verify latest stable)"
  type        = string
  default     = "3.4.2"
}

variable "ca_chart_version" {
  description = "cluster-autoscaler chart version (verify latest stable)"
  type        = string
  default     = "9.58.0"
}
variable "keda_chart_version" {
  description = "KEDA chart version (verify latest stable)"
  type        = string
  default     = "2.20.1"
}

variable "argocd_chart_version" {
  description = "argo-cd chart version (verify latest stable)"
  type        = string
  default     = "10.2.2"
}
