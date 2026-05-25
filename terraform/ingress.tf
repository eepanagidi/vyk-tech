# ──────────────────────────────────────────────
# Ingress NGINX controller (via the ingress-nginx module)
# k3d exposes host ports 8080→80 and 8443→443 via its loadbalancer node.
# ──────────────────────────────────────────────
module "ingress_nginx" {
  source = "./modules/ingress-nginx"

  namespace_labels = merge(local.common_labels, {
    "app.kubernetes.io/name"      = "ingress-nginx"
    "app.kubernetes.io/component" = "ingress"
  })
  helm_common_labels = {
    environment = var.environment
    project     = var.project
    managed_by  = "terraform"
  }
}
