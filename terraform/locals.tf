# ──────────────────────────────────────────────
# locals.tf — Naming, tagging, and protection rules
#
# Resource naming convention:
#   {project}-{component}-{environment}
#   e.g. vyking-platform-argocd-production
#
# Protection rules:
#   production → deletion protection enabled everywhere
#   staging    → deletion protection enabled (soft)
#   local      → no protection (dev teardown must be fast)
# ──────────────────────────────────────────────
locals {

  # ── Naming ───────────────────────────────────
  # All resource names follow: {project}-{component}-{env}
  # Truncated to 63 chars (K8s label value limit)
  name_prefix = substr(
    "${var.project}-${var.environment}",
    0, 48 # Leave room for "-component" suffix
  )

  # Pre-built names for every major resource
  names = {
    argocd           = "${local.name_prefix}-argocd"
    ingress          = "${local.name_prefix}-ingress"
    namespace_argocd = "argocd"         # ArgoCD namespace is fixed by convention
    namespace_infra  = "infrastructure" # K8s namespaces stay generic
    namespace_apps   = "applications"   # so ArgoCD paths don't change per env
  }

  # ── Protection rules ─────────────────────────
  # Is this a protected environment?
  is_protected  = contains(["production", "staging"], var.environment)
  is_production = var.environment == "production"

  # Terraform lifecycle rules:
  #   prevent_destroy = true  → terraform destroy will error unless overridden
  # These are referenced in each resource's lifecycle block.
  # To override in an emergency:
  #   terraform destroy -target=<resource> -var="enable_protection=false"
  enable_protection = var.enable_protection

  # ── Common tags ───────────────────────────────
  # OPA policy enforces these are present on every resource
  common_tags = {
    environment = var.environment
    project     = var.project
    managed_by  = "terraform"
    owner       = var.owner
    repo        = var.git_repo_url
    protected   = tostring(local.is_protected)
  }

  # Kubernetes labels (stricter key rules than Terraform tags)
  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "environment"                  = var.environment
    "project"                      = var.project
    "owner"                        = var.owner
    "vyking.io/protected"          = tostring(local.is_protected)
    "vyking.io/deletion-protected" = tostring(local.enable_protection && local.is_protected)
  }

  # ── ArgoCD sync options per environment ──────
  # Production: manual sync + deletion protection
  # Staging: automated sync + deletion protection
  # Local: automated sync + no protection (fast iteration)
  argocd_sync_options = local.is_production ? [
    "CreateNamespace=true",
    "ServerSideApply=true",
    "PrunePropagationPolicy=foreground",
    "PruneLast=true", # Prune only after all other resources are healthy
    ] : [
    "CreateNamespace=true",
    "ServerSideApply=true",
    "PrunePropagationPolicy=foreground",
  ]

  argocd_automated_sync = local.is_production ? null : {
    prune    = true
    selfHeal = true
  }
}
