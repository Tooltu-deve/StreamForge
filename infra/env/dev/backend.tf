terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.54.0"
    }
  }

  backend "s3" {
    bucket       = "tooltu-streamforge-state"
    region       = "ap-southeast-1"
    key          = "env/dev/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}