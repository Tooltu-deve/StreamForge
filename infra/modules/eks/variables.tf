variable "name_prefix" {
  description = "Name prefix for the app"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "EKS control plane version. Verify GA in ap-southeast-1 before apply (ADR-0006)."
  type        = string
  default     = "1.36"
}

variable "private_subnet_ids" {
  description = "Private subnet ids the cluster and node groups run in"
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint (operator IP allowlist)"
  type        = list(string)
}

variable "cluster_admin_principal_arns" {
  description = "IAM principals granted cluster-admin via EKS Access Entries (operator + CI role)"
  type        = list(string)
}

variable "ondemand_instance_types" {
  description = "Instance types for the on-demand (API) node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "ondemand_scaling" {
  description = "Desired/min/max size for the on-demand node group"
  type = object({
    desired = number
    min     = number
    max     = number
  })
  default = {
    desired = 2
    min     = 1
    max     = 3
  }
}

variable "spot_instance_types" {
  description = "Instance types for the spot (transcode) node group"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "spot_scaling" {
  description = "Desired/min/max size for the spot node group (scale-to-zero at rest)"
  type = object({
    desired = number
    min     = number
    max     = number
  })
  default = {
    desired = 0
    min     = 0
    max     = 4
  }
}

variable "control_plane_log_types" {
  description = "EKS control-plane log types to ship to CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "Retention for the control-plane log group"
  type        = number
  default     = 3
}
