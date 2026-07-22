variable "name_prefix" {
  description = "Name prefix for the app"
  type        = string
}
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}
variable "region" {
  description = "AWS region of the cluster"
  type        = string
}
variable "vpc_id" {
  description = "VPC id the cluster runs in"
  type        = string
}
variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (for IRSA trust)"
  type        = string
}
variable "oidc_provider_url" {
  description = "EKS OIDC provider URL (for IRSA trust condition)"
  type        = string
}
variable "chart_version" {
  description = "aws-load-balancer-controller Helm chart version"
  type        = string
}
