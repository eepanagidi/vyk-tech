#!/usr/bin/env bash
# ──────────────────────────────────────────────
# create-secrets.sh — Apply secrets to cluster
# Secrets are annotated with deletion protection.
# ──────────────────────────────────────────────
set -euo pipefail

MODE="${1:-auto}"

echo "→ Creating namespaces..."
kubectl create namespace infrastructure --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace applications --dry-run=client -o yaml | kubectl apply -f -

# ── Apply MySQL credentials ────────────────────
if [[ "$MODE" == "--sops" ]] || \
   ([[ "$MODE" == "auto" ]] && command -v sops &>/dev/null && \
    [[ -f "secrets/mysql-credentials.enc.yaml" ]]); then
  echo "→ Applying secrets via SOPS..."
  sops --decrypt secrets/mysql-credentials.enc.yaml | kubectl apply -f -
else
  echo "→ Generating random credentials (local dev only)..."
  kubectl create secret generic mysql-credentials \
    --namespace infrastructure \
    --from-literal=mysql-root-password="$(openssl rand -base64 32)" \
    --from-literal=mysql-password="$(openssl rand -base64 32)" \
    --from-literal=mysql-replication-password="$(openssl rand -base64 32)" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

# ── Add protection annotations to the Secret ──
# The Secret is as important as the PVC — losing it means
# MySQL won't start and requires a manual password reset.
echo "→ Annotating mysql-credentials with deletion protection..."
kubectl annotate secret mysql-credentials \
  --namespace infrastructure \
  --overwrite \
  "vyking.io/deletion-protected=true" \
  "vyking.io/contains-stateful-data=true" \
  "vyking.io/purpose=MySQL credentials — loss requires manual DB password reset"

# ── MySQL init ConfigMap ───────────────────────
echo "→ Creating MySQL init ConfigMap..."
kubectl create configmap mysql-initdb \
  --namespace infrastructure \
  --from-file=init.sql=scripts/init.sql \
  --dry-run=client -o yaml | kubectl apply -f -

# ── Copy app credentials to applications namespace ──
echo "→ Copying app credentials to applications namespace..."
APP_PASSWORD=$(kubectl get secret mysql-credentials -n infrastructure \
  -o jsonpath='{.data.mysql-password}' 2>/dev/null || echo "")

if [[ -n "$APP_PASSWORD" ]]; then
  kubectl create secret generic mysql-app-credentials \
    --namespace applications \
    --from-literal=mysql-password="$(echo "$APP_PASSWORD" | base64 -d)" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl annotate secret mysql-app-credentials \
    --namespace applications \
    --overwrite \
    "vyking.io/deletion-protected=true" \
    "vyking.io/purpose=MySQL app-user password for backend pods"
  echo "✓ App credentials copied and annotated."
fi

echo ""
echo "✓ All secrets created and annotated with deletion protection."
echo "  To verify: kubectl get secret mysql-credentials -n infrastructure -o yaml | grep vyking"
