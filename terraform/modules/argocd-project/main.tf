# ──────────────────────────────────────────────
# Module: argocd-project
# A single ArgoCD AppProject. Reusable — the root calls it once per tier
# (infrastructure, applications) via for_each, so the two projects share one
# definition and differ only by inputs.
#
# Applied via gavinbunney/kubectl_manifest so it does not require the argoproj.io
# CRDs at plan time (the ArgoCD bootstrap problem).
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
    kind       = "AppProject"
    metadata = merge({
      name       = var.name
      namespace  = var.namespace
      labels     = var.labels
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }, length(var.annotations) > 0 ? { annotations = var.annotations } : {})
    spec = merge({
      description                = var.description
      sourceRepos                = var.source_repos
      destinations               = var.destinations
      clusterResourceWhitelist   = var.cluster_resource_whitelist
      namespaceResourceWhitelist = var.namespace_resource_whitelist
    }, var.orphaned_resources_warn ? { orphanedResources = { warn = true } } : {})
  })
}
