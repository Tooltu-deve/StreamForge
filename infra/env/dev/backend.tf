terraform {
    backend "s3" {
        bucket = "tooltu-streamforge-state"
        region = "ap-southeast-1"
        key = "env/dev/terraform.tfstate"
        use_lockfile = true
        encrypt = true
    }
}