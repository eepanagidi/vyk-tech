# ──────────────────────────────────────────────
# ArgoCD parent Applications (App-of-Apps)
#
# Applied via kubectl_manifest (not kubernetes_manifest) so they do NOT require
# the argoproj.io CRDs to exist at plan time — see providers.tf for the why.
#
# Named with environment: infrastructure-production, applications-production
# Production: manual sync (no automated prune). Staging/local: automated sync.
# ──────────────────────────────────────────────

resource "kubectl_manifest" "infrastructure_app" {
  depends_on = [
    time_sleep.wait_for_argocd_crds,
    kubectl_manifest.argocd_project_infrastructure,
  ]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "infrastructure-${var.environment}"
      namespace  = var.argocd_namespace
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
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
    }
    spec = {
      project = "infrastructure-${var.environment}"
      source = {
        repoURL        = var.git_repo_url
        targetRevision = var.git_repo_revision
        path           = "infrastructure/argocd-apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.argocd_namespace
      }
      # Production: no automated sync — changes require manual approval in the UI.
      # Staging/local: automated sync + self-heal.
      # Automated sync + self-heal everywhere except production (manual approval).
      syncPolicy = merge(
        {
          syncOptions = local.argocd_sync_options
          retry = {
            limit   = 5
            backoff = { duration = "5s", factor = 2, maxDuration = "3m" }
          }
        },
        local.argocd_automated_sync == null ? {} : { automated = local.argocd_automated_sync }
      )
    }
  })
}

resource "kubectl_manifest" "applications_app" {
  depends_on = [
    time_sleep.wait_for_argocd_crds,
    kubectl_manifest.argocd_project_applications,
  ]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "applications-${var.environment}"
      namespace  = var.argocd_namespace
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
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
    }
    spec = {
      project = "applications-${var.environment}"
      source = {
        repoURL        = var.git_repo_url
        targetRevision = var.git_repo_revision
        path           = "applications"
        helm = {
          valueFiles = ["values.yaml"]
          # Pass environment into Helm so resource names include it
          parameters = [
            { name = "global.environment", value = var.environment },
            { name = "global.commonLabels.environment", value = var.environment },
          ]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "applications"
      }
      # Automated sync + self-heal everywhere except production (manual approval).
      syncPolicy = merge(
        {
          syncOptions = local.argocd_sync_options
          retry = {
            limit   = 5
            backoff = { duration = "5s", factor = 2, maxDuration = "3m" }
          }
        },
        local.argocd_automated_sync == null ? {} : { automated = local.argocd_automated_sync }
      )
    }
  })
}
