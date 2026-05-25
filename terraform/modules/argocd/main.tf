# ──────────────────────────────────────────────
# Module: argocd
# Installs ArgoCD via Helm into its own namespace, and (for a private repo)
# creates the repository credential Secret ArgoCD uses to authenticate git fetches.
# ──────────────────────────────────────────────
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
  }
}

resource "kubernetes_namespace" "this" {
  metadata {
    name        = var.namespace
    labels      = var.namespace_labels
    annotations = var.namespace_annotations
  }

  lifecycle {
    # Durability is enforced below Terraform (PV Retain, backups, Gatekeeper),
    # not via prevent_destroy, so local `terraform destroy` works cleanly.
    ignore_changes = [metadata[0].labels["kubectl.kubernetes.io/last-applied-configuration"]]
  }
}

resource "helm_release" "this" {
  name       = var.release_name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.this.metadata[0].name

  wait    = true
  timeout = 600
  atomic  = true

  # global.commonLabels.<key> = <value> for every entry in helm_common_labels
  dynamic "set" {
    for_each = var.helm_common_labels
    content {
      name  = "global.commonLabels.${set.key}"
      value = set.value
    }
  }

  values = [file("${path.module}/argocd-values.yaml")]

  depends_on = [kubernetes_namespace.this]
}

# ArgoCD watches Secrets labeled argocd.argoproj.io/secret-type=repository and
# uses them to authenticate git fetches. Only created when a token is supplied.
resource "kubernetes_secret" "repo" {
  count = var.github_token != "" ? 1 : 0

  metadata {
    name      = "repo-vyk-tech"
    namespace = kubernetes_namespace.this.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    type     = "git"
    url      = var.git_repo_url
    username = var.git_username
    password = var.github_token
  }
  depends_on = [helm_release.this]
}
