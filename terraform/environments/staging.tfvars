# ── Staging ───────────────────────────────────
# Protection enabled, automated ArgoCD sync (mirrors prod workflow)
environment       = "staging"
kube_context      = "k8s-staging"
enable_protection = true

# Resource names: vyking-platform-staging-argocd, backend-staging, etc.
