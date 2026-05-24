# ── Production ────────────────────────────────
# Full protection, MANUAL ArgoCD sync (every change requires UI approval)
environment       = "production"
kube_context      = "k8s-production"
enable_protection = true

# Resource names: vyking-platform-production-argocd, backend-production, etc.
#
# DESTROY PROCEDURE (break-glass):
#   1. terraform apply -var-file=environments/production.tfvars \
#        -var="enable_protection=false"  ← removes prevent_destroy
#   2. terraform destroy -var-file=environments/production.tfvars \
#        -var="enable_protection=false"
#   3. Requires two-person approval in your change management process
