# ──────────────────────────────────────────────
# Ingress NGINX controller
# Deployed via Helm, managed by Terraform
# k3d exposes ports 8080→80 and 8443→443 via loadbalancer node
# ──────────────────────────────────────────────
resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/name"      = "ingress-nginx"
      "app.kubernetes.io/component" = "ingress"
    })
  }
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.10.1" # Pinned
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name

  # Non-blocking: on local k3d the controller can take a while to pull/settle,
  # and it is NOT on the critical path (the app is verified via port-forward).
  # k8s converges it asynchronously — check with `kubectl -n ingress-nginx get po`.
  wait   = false
  atomic = false

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
  # Security: drop privileges
  set {
    name  = "controller.podSecurityContext.runAsNonRoot"
    value = "true"
  }
  set {
    name  = "controller.containerSecurityContext.allowPrivilegeEscalation"
    value = "false"
  }
  set {
    name  = "controller.containerSecurityContext.readOnlyRootFilesystem"
    value = "false" # nginx-ingress writes to /tmp at runtime
  }
  # The admission webhook's pre-install Job is the most common cause of a slow/
  # stuck ingress-nginx install on local k3d, and it isn't needed to serve
  # Ingress traffic for this demo — disable it locally.
  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "false"
  }
  # Resources
  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }
  set {
    name  = "controller.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "controller.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "controller.resources.limits.memory"
    value = "512Mi"
  }
  # Common labels
  set {
    name  = "commonLabels.environment"
    value = var.environment
  }
  set {
    name  = "commonLabels.project"
    value = var.project
  }
  set {
    name  = "commonLabels.managed_by"
    value = "terraform"
  }

  depends_on = [kubernetes_namespace.ingress_nginx]
}
