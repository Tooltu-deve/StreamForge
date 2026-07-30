output "controller_role_arn" {
  value = module.alb_controller.controller_role_arn
}

output "svc_role_arns" {
  description = "Map service => IRSA role ARN"
  value       = { for k, r in aws_iam_role.svc : k => r.arn }
}

output "cluster_autoscaler_role_arn" { value = module.cluster_autoscaler.role_arn }
output "keda_operator_role_arn" { value = module.keda.operator_role_arn }
