# ──────────────────────────────────────────────
# moved {} blocks — record that resources were relocated into modules during the
# refactor. Terraform treats these as state renames (NOT destroy/recreate), so an
# existing cluster is left untouched. `terraform plan` must show "No changes".
# These can be removed once all state has been applied past this refactor.
# ──────────────────────────────────────────────

# ArgoCD install → module.argocd
moved {
  from = kubernetes_namespace.argocd
  to   = module.argocd.kubernetes_namespace.this
}
moved {
  from = helm_release.argocd
  to   = module.argocd.helm_release.this
}
moved {
  from = kubernetes_secret.argocd_repo[0]
  to   = module.argocd.kubernetes_secret.repo[0]
}

# ingress-nginx → module.ingress_nginx
moved {
  from = kubernetes_namespace.ingress_nginx
  to   = module.ingress_nginx.kubernetes_namespace.this
}
moved {
  from = helm_release.ingress_nginx
  to   = module.ingress_nginx.helm_release.this
}

# AppProjects → per-tier argocd-project modules
moved {
  from = kubectl_manifest.argocd_project_infrastructure
  to   = module.argocd_project_infrastructure.kubectl_manifest.this
}
moved {
  from = kubectl_manifest.argocd_project_applications
  to   = module.argocd_project_applications.kubectl_manifest.this
}

# Parent Applications → per-tier argocd-application modules
moved {
  from = kubectl_manifest.infrastructure_app
  to   = module.argocd_application_infrastructure.kubectl_manifest.this
}
moved {
  from = kubectl_manifest.applications_app
  to   = module.argocd_application_applications.kubectl_manifest.this
}
