module "vpc" {
  source          = "../../modules/vpc"
  name_prefix     = var.name_prefix
  cluster_name    = var.cluster_name
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

module "s3" {
  source      = "../../modules/s3"
  name_prefix = var.name_prefix
  app_domain  = var.app_domain
}

resource "aws_s3_bucket_notification" "raw_eventbridge" {
  bucket      = module.s3.bucket_names["raw"]
  eventbridge = true
}

module "sqs" {
  source         = "../../modules/sqs"
  name_prefix    = var.name_prefix
  raw_bucket_arn = module.s3.bucket_arns["raw"]
}

module "dynamodb" {
  source      = "../../modules/dynamodb"
  name_prefix = var.name_prefix
}

module "cognito" {
  source      = "../../modules/cognito"
  name_prefix = var.name_prefix
}

module "ecr" {
  source      = "../../modules/ecr"
  name_prefix = var.name_prefix
  services    = var.ecr_services
}

module "eks" {
  source       = "../../modules/eks"
  name_prefix  = var.name_prefix
  cluster_name = var.cluster_name

  private_subnet_ids           = module.vpc.private_subnet_ids # ← nối vpc → eks
  public_access_cidrs          = var.public_access_cidrs
  cluster_admin_principal_arns = var.cluster_admin_principal_arns
}

# CloudFront + its ALB/cert data sources moved to infra/edge/dev (edge layer) so the
# ALB lookup lives in a layer torn down before the ALB, killing the destroy-time jam.

resource "aws_secretsmanager_secret" "cf_signing" {
  name                    = "streamforge-dev/cf-signing"
  recovery_window_in_days = 0
}