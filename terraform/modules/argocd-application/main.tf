# ──────────────────────────────────────────────
# Module: argocd-application
# A single ArgoCD (parent) Application. Reusable — the root calls it once per
# tier (infrastructure, applications) via for_each.
#
# Applied via gavinbunney/kubectl_manifest so it does not require the argoproj.io
# CRDs at plan time.
# ──────────────────────────────────────────────
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

resource "kubectl_manifest" "this" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name        = var.name
      namespace   = var.namespace
      finalizers  = ["resources-finalizer.argocd.argoproj.io"]
      labels      = var.labels
      annotations = var.annotations
    }
    spec = {
      project = var.project
      source = merge({
        repoURL        = var.repo_url
        targetRevision = var.target_revision
        path           = var.source_path
      }, var.source_helm == null ? {} : { helm = var.source_helm })
      destination = {
        server    = var.dest_server
        namespace = var.dest_namespace
      }
      syncPolicy = merge({
        syncOptions = var.sync_options
        retry = {
          limit   = 5
          backoff = { duration = "5s", factor = 2, maxDuration = "3m" }
        }
      }, var.automated == null ? {} : { automated = var.automated })
    }
  })
}
