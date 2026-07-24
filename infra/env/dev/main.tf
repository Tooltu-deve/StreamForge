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

data "aws_lb" "api" {
  tags = {
    "ingress.k8s.aws/stack" = "streamforge/streamforge"
  }
}

data "aws_acm_certificate" "cf" {
  provider    = aws.us_east_1
  domain      = var.app_domain # "app.<domain>"
  statuses    = ["ISSUED"]
  most_recent = true
}

module "cloudfront" {
  source                 = "../../modules/cloudfront"
  frontend_bucket_id     = module.s3.bucket_names["frontend"]
  frontend_bucket_arn    = module.s3.bucket_arns["frontend"]
  frontend_bucket_domain = "${module.s3.bucket_names["frontend"]}.s3.${var.region}.amazonaws.com"
  alb_dns_name           = data.aws_lb.api.dns_name
  acm_cert_arn           = data.aws_acm_certificate.cf.arn
  aliases                = [var.app_domain]
  origin_secret          = var.origin_secret
}