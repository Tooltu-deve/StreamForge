resource "aws_s3_bucket" "this" {
  for_each      = toset(["raw", "transcoded", "frontend"])
  bucket        = "${var.name_prefix}-${each.key}"
  force_destroy = true
  tags = {
    "Name" = "${var.name_prefix}-${each.key}"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_cors_configuration" "raw" {
  bucket = aws_s3_bucket.this["raw"].id
  cors_rule {
    allowed_methods = ["PUT", "GET"]
    allowed_origins = ["https://${var.app_domain}"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.this["frontend"].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}


resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.this["raw"].id
  rule {
    id = "rule-1"
    filter {}
    status = "Enabled"
    expiration {
      days = var.raw_expiration_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

