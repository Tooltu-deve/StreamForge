data "terraform_remote_state" "core" {
  backend = "s3"
  config = {
    bucket = var.core_state_bucket
    key    = var.core_state_key
    region = var.region
  }
}

module "alb_controller" {
  source = "../../modules/alb-controller"

  name_prefix       = var.name_prefix
  cluster_name      = data.terraform_remote_state.core.outputs.cluster_name
  region            = var.region
  vpc_id            = data.terraform_remote_state.core.outputs.vpc_id
  oidc_provider_arn = data.terraform_remote_state.core.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.core.outputs.oidc_provider_url
  chart_version     = var.lbc_chart_version
}

module "cluster_autoscaler" {
  source            = "../../modules/cluster-autoscaler"
  name_prefix       = var.name_prefix
  cluster_name      = data.terraform_remote_state.core.outputs.cluster_name
  region            = var.region
  oidc_provider_arn = data.terraform_remote_state.core.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.core.outputs.oidc_provider_url
  chart_version     = var.ca_chart_version
  depends_on = [module.alb_controller]
}

module "keda" {
  source            = "../../modules/keda"
  name_prefix       = var.name_prefix
  region            = var.region
  oidc_provider_arn = data.terraform_remote_state.core.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.core.outputs.oidc_provider_url
  queue_arn         = data.terraform_remote_state.core.outputs.queue_arn
  chart_version     = var.keda_chart_version
  depends_on = [module.alb_controller]
}
