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

  # A single YAML values block (not many `set` lines): overriding
  # controller.containerSecurityContext piecemeal silently DROPS the chart's
  # defaults (runAsUser: 101, capabilities), and a pod with runAsNonRoot: true
  # but no NUMERIC runAsUser fails with CreateContainerConfigError ("image has
  # non-numeric user www-data, cannot verify user is non-root"). Set the full
  # securityContext explicitly so the controller can start AND stays hardened.
  values = [yamlencode({
    controller = {
      service = { type = "LoadBalancer" }

      podSecurityContext = {
        runAsNonRoot   = true
        runAsUser      = 101 # www-data (numeric — required when runAsNonRoot=true)
        seccompProfile = { type = "RuntimeDefault" }
      }

      containerSecurityContext = {
        runAsNonRoot             = true
        runAsUser                = 101
        allowPrivilegeEscalation = false
        readOnlyRootFilesystem   = false # nginx writes to /tmp + /etc/nginx at runtime
        capabilities = {
          drop = ["ALL"]
          add  = ["NET_BIND_SERVICE"] # bind :80/:443 as a non-root user
        }
      }

      # The admission webhook's pre-install Job is the most common cause of a
      # slow/stuck ingress-nginx install on local k3d, and it isn't needed to
      # serve Ingress traffic for this demo — disable it locally.
      admissionWebhooks = { enabled = false }

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }

    commonLabels = {
      environment = var.environment
      project     = var.project
      managed_by  = "terraform"
    }
  })]

  depends_on = [kubernetes_namespace.ingress_nginx]
}
