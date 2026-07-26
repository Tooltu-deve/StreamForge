provider "aws" {
  region = var.region
  default_tags {
    tags = {
      project    = "streamforge"
      env        = "dev"
      managed-by = "terraform"
    }
  }
}

# CloudFront requires its ACM certificate to live in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      project    = "streamforge"
      env        = "dev"
      managed-by = "terraform"
    }
  }
}
