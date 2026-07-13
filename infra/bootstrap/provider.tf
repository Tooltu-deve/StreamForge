provider "aws" {
  region = var.region
  default_tags {
    tags = {
      project    = "streamforge",
      env        = "bootstrap"
      managed-by = "terraform"
    }
  }
}