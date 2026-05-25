# ──────────────────────────────────────────────
# ArgoCD parent Applications (App-of-Apps), one reusable module per tier.
#
# Applied via the argocd-application module (kubectl_manifest) so they do NOT
# require the argoproj.io CRDs at plan time.
# Production: manual sync (automated = null). Staging/local: automated + self-heal.
# ──────────────────────────────────────────────

module "argocd_application_infrastructure" {
  source = "./modules/argocd-application"

  name      = "infrastructure-${var.environment}"
  namespace = var.argocd_namespace
  project   = "infrastructure-${var.environment}"

  labels = merge(local.common_labels, {
    "app.kubernetes.io/name"      = "infrastructure-${var.environment}"
    "app.kubernetes.io/component" = "gitops-parent"
  })
  annotations = merge({
    "vyking.io/deletion-protected"                             = tostring(local.is_protected)
    "vyking.io/environment"                                    = var.environment
    "notifications.argoproj.io/subscribe.on-sync-failed.slack" = "devops-alerts"
    }, local.is_production ? {
    "notifications.argoproj.io/subscribe.on-sync-succeeded.slack" = "devops-syncs"
  } : {})

  repo_url        = var.git_repo_url
  target_revision = var.git_repo_revision
  source_path     = "infrastructure/argocd-apps"
  dest_namespace  = var.argocd_namespace

  sync_options = local.argocd_sync_options
  automated    = local.argocd_automated_sync

  depends_on = [
    time_sleep.wait_for_argocd_crds,
    module.argocd_project_infrastructure,
  ]
}

module "argocd_application_applications" {
  source = "./modules/argocd-application"

  name      = "applications-${var.environment}"
  namespace = var.argocd_namespace
  project   = "applications-${var.environment}"

  labels = merge(local.common_labels, {
    "app.kubernetes.io/name"      = "applications-${var.environment}"
    "app.kubernetes.io/component" = "gitops-parent"
  })
  annotations = merge({
    "vyking.io/deletion-protected"                             = tostring(local.is_protected)
    "vyking.io/environment"                                    = var.environment
    "notifications.argoproj.io/subscribe.on-sync-failed.slack" = "devops-alerts"
    }, local.is_production ? {
    "notifications.argoproj.io/subscribe.on-sync-succeeded.slack" = "devops-syncs"
  } : {})

  repo_url        = var.git_repo_url
  target_revision = var.git_repo_revision
  source_path     = "applications"
  dest_namespace  = "applications"
  source_helm = {
    valueFiles = ["values.yaml"]
    # Pass environment into Helm so resource names include it
    parameters = [
      { name = "global.environment", value = var.environment },
      { name = "global.commonLabels.environment", value = var.environment },
    ]
  }

  sync_options = local.argocd_sync_options
  automated    = local.argocd_automated_sync

  depends_on = [
    time_sleep.wait_for_argocd_crds,
    module.argocd_project_applications,
  ]
}
