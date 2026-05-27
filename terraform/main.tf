# ──────────────────────────────────────────────
# main.tf — root composition
#
# Terraform's job is the bootstrap only: install ArgoCD + ingress-nginx and
# define the two parent Applications + their AppProjects. Everything else
# (MySQL, the app chart, backups, gatekeeper) is GitOps-managed by ArgoCD.
#
# Reusable modules live in ./modules and are invoked once per tier.
# ──────────────────────────────────────────────

# The 'infrastructure' and 'applications' namespaces are created by
# scripts/create-secrets.sh (before `terraform apply`, so the MySQL Secret and
# initdb ConfigMap can be placed in them) and are also covered by each ArgoCD
# app's CreateNamespace=true sync option. Terraform deliberately does NOT manage
# them — doing so collided with the pre-created namespaces ("already exists").

# ── ArgoCD (install + repository credential) ──────────────────────────────────
module "argocd" {
  source = "./modules/argocd"

  release_name  = local.names.argocd
  namespace     = var.argocd_namespace
  chart_version = var.argocd_chart_version

  namespace_labels = merge(local.common_labels, {
    "app.kubernetes.io/name"             = local.names.argocd
    "app.kubernetes.io/component"        = "gitops"
    "pod-security.kubernetes.io/enforce" = "baseline"
    "pod-security.kubernetes.io/warn"    = "restricted"
  })
  namespace_annotations = {
    "meta.helm.sh/release-name"      = local.names.argocd
    "meta.helm.sh/release-namespace" = var.argocd_namespace
    "vyking.io/deletion-protected"   = tostring(local.enable_protection && local.is_protected)
  }
  helm_common_labels = {
    environment = var.environment
    project     = var.project
    owner       = var.owner
    managed_by  = "terraform"
    protected   = tostring(local.is_protected)
  }

  git_repo_url = var.git_repo_url
  git_username = var.git_username
  github_token = var.github_token
}

# Give ArgoCD time to register its CRDs before we create AppProjects/Applications.
resource "time_sleep" "wait_for_argocd_crds" {
  depends_on      = [module.argocd]
  create_duration = "45s"
}

# ── AppProjects — one reusable module, invoked per tier ───────────────────────
module "argocd_project_infrastructure" {
  source = "./modules/argocd-project"

  name        = "infrastructure-${var.environment}"
  namespace   = var.argocd_namespace
  description = "Infrastructure workloads (${var.environment}): MySQL, backup CronJob"
  labels      = local.common_labels
  annotations = {
    "vyking.io/deletion-protected" = tostring(local.is_protected)
  }

  source_repos = [var.git_repo_url, "https://charts.bitnami.com/bitnami"]
  destinations = [
    { server = "https://kubernetes.default.svc", namespace = "infrastructure" },
    { server = "https://kubernetes.default.svc", namespace = "gatekeeper-system" },
    # App-of-Apps: the parent creates child Application CRs in argocd
    { server = "https://kubernetes.default.svc", namespace = "argocd" },
  ]
  cluster_resource_whitelist = [
    { group = "", kind = "Namespace" },
    { group = "storage.k8s.io", kind = "StorageClass" }, # platform-base creates mysql-retain
  ]
  namespace_resource_whitelist = [
    { group = "", kind = "ConfigMap" },
    { group = "", kind = "PersistentVolumeClaim" },
    { group = "", kind = "Secret" },
    { group = "", kind = "Service" },
    { group = "", kind = "ServiceAccount" },
    { group = "apps", kind = "StatefulSet" },
    { group = "batch", kind = "CronJob" },
    { group = "batch", kind = "Job" },
    { group = "rbac.authorization.k8s.io", kind = "Role" },
    { group = "rbac.authorization.k8s.io", kind = "RoleBinding" },
    { group = "networking.k8s.io", kind = "NetworkPolicy" },
    { group = "policy", kind = "PodDisruptionBudget" },           # Bitnami MySQL chart creates one
    { group = "monitoring.coreos.com", kind = "ServiceMonitor" }, # MySQL exporter scrape target
    { group = "argoproj.io", kind = "Application" },              # App-of-Apps child Applications
    { group = "templates.gatekeeper.sh", kind = "ConstraintTemplate" },
    { group = "constraints.gatekeeper.sh", kind = "*" },
  ]
  orphaned_resources_warn = local.is_production

  depends_on = [time_sleep.wait_for_argocd_crds]
}

module "argocd_project_applications" {
  source = "./modules/argocd-project"

  name        = "applications-${var.environment}"
  namespace   = var.argocd_namespace
  description = "Frontend and backend workloads (${var.environment})"
  labels      = local.common_labels

  source_repos = [var.git_repo_url]
  destinations = [
    { server = "https://kubernetes.default.svc", namespace = "applications" },
  ]
  cluster_resource_whitelist = []
  namespace_resource_whitelist = [
    { group = "", kind = "ConfigMap" },
    { group = "", kind = "Service" },
    { group = "", kind = "ServiceAccount" },
    { group = "apps", kind = "Deployment" },
    { group = "autoscaling", kind = "HorizontalPodAutoscaler" },
    { group = "policy", kind = "PodDisruptionBudget" },
    { group = "networking.k8s.io", kind = "NetworkPolicy" },
    { group = "networking.k8s.io", kind = "Ingress" },
    { group = "rbac.authorization.k8s.io", kind = "Role" },
    { group = "rbac.authorization.k8s.io", kind = "RoleBinding" },
  ]
  orphaned_resources_warn = local.is_production

  depends_on = [time_sleep.wait_for_argocd_crds]
}
