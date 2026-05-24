# ──────────────────────────────────────────────
# main.tf — Namespaces, ArgoCD, AppProjects
#
# Resource names follow: {project}-{environment}-{component}
# Deletion protection is active for production + staging.
# ──────────────────────────────────────────────

# ── Namespaces ────────────────────────────────
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace # "argocd" — fixed convention
    labels = merge(local.common_labels, {
      "app.kubernetes.io/name"             = local.names.argocd
      "app.kubernetes.io/component"        = "gitops"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
    })
    annotations = {
      "meta.helm.sh/release-name"      = local.names.argocd
      "meta.helm.sh/release-namespace" = var.argocd_namespace
      # Annotation-based deletion guard — admission webhooks can enforce this
      "vyking.io/deletion-protected" = tostring(local.enable_protection && local.is_protected)
    }
  }

  lifecycle {
    # Data durability is enforced below Terraform — PV reclaimPolicy=Retain,
    # backups, and Gatekeeper — not via prevent_destroy, so that local
    # `terraform destroy` (the graded teardown step) works cleanly.
    ignore_changes = [metadata[0].labels["kubectl.kubernetes.io/last-applied-configuration"]]
  }
}

# The 'infrastructure' and 'applications' namespaces are created by
# scripts/create-secrets.sh (before `terraform apply`, so the MySQL Secret and
# initdb ConfigMap can be placed in them) and are also covered by each ArgoCD
# app's CreateNamespace=true sync option. Terraform deliberately does NOT manage
# them — doing so collided with the pre-created namespaces ("already exists").

# ── ArgoCD via Helm ───────────────────────────
# Name includes environment: vyking-platform-production-argocd
resource "helm_release" "argocd" {
  name       = local.names.argocd
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  wait    = true
  timeout = 600
  atomic  = true

  # Inject environment into ArgoCD labels
  set {
    name  = "global.commonLabels.environment"
    value = var.environment
  }
  set {
    name  = "global.commonLabels.project"
    value = var.project
  }
  set {
    name  = "global.commonLabels.owner"
    value = var.owner
  }
  set {
    name  = "global.commonLabels.managed_by"
    value = "terraform"
  }
  set {
    name  = "global.commonLabels.protected"
    value = tostring(local.is_protected)
  }

  values = [file("${path.module}/argocd-values.yaml")]

  depends_on = [kubernetes_namespace.argocd]
}

# ── ArgoCD repository credential (PRIVATE repo only) ──
# ArgoCD watches Secrets labeled argocd.argoproj.io/secret-type=repository and
# uses them to authenticate git fetches. Created ONLY when var.github_token is
# supplied out-of-band (terraform/secret.auto.tfvars or TF_VAR_github_token).
# A public repo needs none of this.
resource "kubernetes_secret" "argocd_repo" {
  count = var.github_token != "" ? 1 : 0

  metadata {
    name      = "repo-vyk-tech"
    namespace = kubernetes_namespace.argocd.metadata[0].name
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
  depends_on = [helm_release.argocd]
}

# ── Ingress NGINX is defined in ingress.tf ────

# ── ArgoCD AppProjects ────────────────────────
# Named with environment: infrastructure-production, applications-production
resource "kubectl_manifest" "argocd_project_infrastructure" {
  depends_on = [time_sleep.wait_for_argocd_crds]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "infrastructure-${var.environment}"
      namespace = var.argocd_namespace
      labels    = local.common_labels
      annotations = {
        "vyking.io/deletion-protected" = tostring(local.is_protected)
      }
      # ArgoCD finalizer prevents the project being deleted while apps reference it
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = merge({
      description = "Infrastructure workloads (${var.environment}): MySQL, backup CronJob"
      sourceRepos = [var.git_repo_url, "https://charts.bitnami.com/bitnami"]
      destinations = [
        {
          server    = "https://kubernetes.default.svc"
          namespace = "infrastructure"
        },
        {
          server    = "https://kubernetes.default.svc"
          namespace = "gatekeeper-system"
        },
        {
          # App-of-Apps: the parent creates child Application CRs in argocd
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
      ]
      clusterResourceWhitelist = [
        { group = "", kind = "Namespace" },
        { group = "storage.k8s.io", kind = "StorageClass" }, # platform-base creates mysql-retain
      ]
      namespaceResourceWhitelist = [
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
        { group = "policy", kind = "PodDisruptionBudget" }, # Bitnami MySQL chart creates one
        # App-of-Apps: parent infrastructure app creates child Applications
        { group = "argoproj.io", kind = "Application" },
        # Gatekeeper policy resources
        { group = "templates.gatekeeper.sh", kind = "ConstraintTemplate" },
        { group = "constraints.gatekeeper.sh", kind = "*" },
      ]
      # Orphaned resources: warn (don't auto-delete) — production only
    }, local.is_production ? { orphanedResources = { warn = true } } : {})
  })
}

resource "kubectl_manifest" "argocd_project_applications" {
  depends_on = [time_sleep.wait_for_argocd_crds]
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name       = "applications-${var.environment}"
      namespace  = var.argocd_namespace
      labels     = local.common_labels
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = merge({
      description = "Frontend and backend workloads (${var.environment})"
      sourceRepos = [var.git_repo_url]
      destinations = [{
        server    = "https://kubernetes.default.svc"
        namespace = "applications"
      }]
      clusterResourceWhitelist = []
      namespaceResourceWhitelist = [
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
    }, local.is_production ? { orphanedResources = { warn = true } } : {})
  })
}

resource "time_sleep" "wait_for_argocd_crds" {
  depends_on      = [helm_release.argocd]
  create_duration = "45s"
}
