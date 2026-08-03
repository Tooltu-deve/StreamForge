variable "chart_version" {
  description = "argo-cd Helm chart version (verify latest stable before apply)"
  type        = string
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the public streamforge-gitops repo"
  type        = string
}
variable "gitops_revision" {
  description = "Branch/tag ArgoCD tracks"
  type        = string
  default     = "main"
}
