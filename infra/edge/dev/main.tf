data "terraform_remote_state" "core" {
  backend = "s3"
  config = {
    bucket = var.core_state_bucket
    key    = var.core_state_key
    region = var.region
  }
}

# The ALB is created out-of-band by the AWS Load Balancer Controller (Helm ingress),
# so it only exists once the platform layer + app are deployed. Reading it here — in
# a layer torn down BEFORE the ALB — avoids the destroy-time "empty result" that used
# to jam core. Apply order: core -> platform (creates ALB) -> edge.
data "aws_lb" "api" {
  tags = {
    "ingress.k8s.aws/stack" = "streamforge/streamforge"
  }
}

data "aws_acm_certificate" "cf" {
  provider    = aws.us_east_1
  domain      = var.cf_cert_domain
  statuses    = ["ISSUED"]
  most_recent = true
}

module "cloudfront" {
  source                   = "../../modules/cloudfront"
  frontend_bucket_id       = data.terraform_remote_state.core.outputs.bucket_names["frontend"]
  frontend_bucket_arn      = data.terraform_remote_state.core.outputs.frontend_bucket_arn
  frontend_bucket_domain   = "${data.terraform_remote_state.core.outputs.bucket_names["frontend"]}.s3.${var.region}.amazonaws.com"
  transcoded_bucket_id     = data.terraform_remote_state.core.outputs.bucket_names["transcoded"]
  transcoded_bucket_arn    = data.terraform_remote_state.core.outputs.transcoded_bucket_arn
  transcoded_bucket_domain = "${data.terraform_remote_state.core.outputs.bucket_names["transcoded"]}.s3.${var.region}.amazonaws.com"
  alb_dns_name             = data.aws_lb.api.dns_name
  acm_cert_arn             = data.aws_acm_certificate.cf.arn
  aliases                  = [var.app_domain]
  origin_secret            = var.origin_secret
}
