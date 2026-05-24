terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

# The kubectl provider applies ArgoCD Application/AppProject CRs via server-side
# apply WITHOUT needing the argoproj.io CRDs to exist at plan time. That is what
# lets one `terraform apply` install ArgoCD (Helm) and create its Applications in
# a single pass — hashicorp/kubernetes_manifest cannot, because it resolves the
# resource schema from the live API at plan time (classic CRD bootstrap problem).
provider "kubectl" {
  config_path      = var.kubeconfig_path
  config_context   = var.kube_context
  load_config_file = true
}
