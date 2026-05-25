# ──────────────────────────────────────────────
# Module: ingress-nginx
# Installs the ingress-nginx controller via Helm. The container securityContext
# is set as one block (overriding it piecemeal drops the chart's numeric
# runAsUser: 101 and caps, which fails the pod with CreateContainerConfigError).
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
    name   = "ingress-nginx"
    labels = var.namespace_labels
  }
}

resource "helm_release" "this" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.10.1" # Pinned

  namespace = kubernetes_namespace.this.metadata[0].name

  # Non-blocking: on local k3d the controller can take a while to settle and it
  # is not on the critical path (the app is verified via port-forward).
  wait   = false
  atomic = false

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
      # stuck ingress-nginx install on local k3d, and it isn't needed for the demo.
      admissionWebhooks = { enabled = false }

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }

    commonLabels = var.helm_common_labels
  })]

  depends_on = [kubernetes_namespace.this]
}
