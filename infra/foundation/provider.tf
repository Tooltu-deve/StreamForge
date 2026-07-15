provider "aws" {
  region = var.region
  default_tags {
    tags = {
      project    = "streamforge",
      env        = "foundation"
      managed-by = "terraform"
    }
  }
}