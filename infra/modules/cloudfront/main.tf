resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "streamforge-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_control" "transcoded" {
  name                              = "streamforge-transcoded-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = var.aliases

  origin {
    origin_id                = "s3-frontend"
    domain_name              = var.frontend_bucket_domain
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    origin_id                = "s3-transcoded"
    domain_name              = var.transcoded_bucket_domain
    origin_access_control_id = aws_cloudfront_origin_access_control.transcoded.id
  }

  origin {
    origin_id   = "alb-api"
    domain_name = var.alb_dns_name
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
    custom_header {
      name  = "X-Origin-Secret"
      value = var.origin_secret
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "alb-api"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader
  }

  ordered_cache_behavior {
    path_pattern           = "/hls/*"
    target_origin_id       = "s3-transcoded"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    trusted_key_groups     = [aws_cloudfront_key_group.signing.id]
  }

  ordered_cache_behavior {
    path_pattern           = "/thumbs/*"
    target_origin_id       = "s3-transcoded"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_cert_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

}

# S3 frontend chỉ cho CloudFront (OAC) đọc
data "aws_iam_policy_document" "frontend" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.frontend_bucket_arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

data "aws_iam_policy_document" "transcoded" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.transcoded_bucket_arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "transcoded" {
  bucket = var.transcoded_bucket_id
  policy = data.aws_iam_policy_document.transcoded.json
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.frontend_bucket_id
  policy = data.aws_iam_policy_document.frontend.json
}

resource "aws_cloudfront_public_key" "signing" {
  name        = "streamforge-dev-signing"
  encoded_key = var.signing_public_key_pem
  comment     = "HLS signed-cookie key"
}

resource "aws_cloudfront_key_group" "signing" {
  name  = "streamforge-dev-signing"
  items = [aws_cloudfront_public_key.signing.id]
}