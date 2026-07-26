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

# helm provider v3: kubernetes config + exec là attribute (= {...}), không phải block lồng
provider "helm" {
  kubernetes = {
    host                   = data.terraform_remote_state.core.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.core.outputs.cluster_ca_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.core.outputs.cluster_name, "--region", var.region]
    }
  }
}
