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

