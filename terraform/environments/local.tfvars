# ── Local development ─────────────────────────
# Fast iteration — no deletion protection, automated ArgoCD sync
environment       = "local"
kube_context      = "k3d-vyking-cluster"
enable_protection = false

# Resource names will be: vyking-platform-local-argocd, backend-local, etc.
