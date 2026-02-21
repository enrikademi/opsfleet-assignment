terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.18"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
  }
}
