#!/usr/bin/env bash
# Full environment teardown
set -uo pipefail
cd "$(dirname "$0")/.."

# Lift Gatekeeper deletion-protection first. The constraints run in `deny` mode,
# so they would otherwise block ArgoCD from deleting MySQL during destroy. We
# remove the validating webhook + constraints (best-effort); GitOps can't recreate
# them once ArgoCD is gone, and `k3d cluster delete` below is the final backstop.
echo "→ Lifting Gatekeeper deletion-protection so protected resources can be torn down..."
kubectl delete validatingwebhookconfiguration gatekeeper-validating-webhook-configuration --ignore-not-found --wait=false 2>/dev/null || true
kubectl delete deletionprotection --all --ignore-not-found --wait=false 2>/dev/null || true

echo "→ Destroying Terraform resources..."
( cd terraform && terraform destroy -auto-approve ) || echo "⚠ terraform destroy failed/partial — continuing to delete the cluster."

echo "→ Deleting k3d cluster (removes everything regardless)..."
k3d cluster delete vyking-cluster || true

echo "✓ Environment fully torn down."
