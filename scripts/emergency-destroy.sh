#!/usr/bin/env bash
# ──────────────────────────────────────────────
# EMERGENCY DESTROY — bypasses deletion protection
#
# Requires:
#   1. ENV variable set to target environment
#   2. Confirmation typed explicitly
#   3. Reason logged
#
# Usage:
#   ENV=production REASON="decommission" ./scripts/emergency-destroy.sh
# ──────────────────────────────────────────────
set -euo pipefail

ENV="${ENV:-}"
REASON="${REASON:-}"

if [[ -z "$ENV" || -z "$REASON" ]]; then
  echo "ERROR: Both ENV and REASON must be set."
  echo "Usage: ENV=production REASON='decommission Q4' ./scripts/emergency-destroy.sh"
  exit 1
fi

echo ""
echo "⚠️  EMERGENCY DESTROY"
echo "   Environment : $ENV"
echo "   Reason      : $REASON"
echo "   Operator    : $(whoami)@$(hostname)"
echo "   Timestamp   : $(date -u)"
echo ""
echo "This will PERMANENTLY DELETE all resources in the $ENV environment."
echo "Type the environment name to confirm: "
read -r CONFIRM

if [[ "$CONFIRM" != "$ENV" ]]; then
  echo "Confirmation mismatch. Aborting."
  exit 1
fi

# Log the action (append to audit log)
echo "$(date -u) | EMERGENCY_DESTROY | env=$ENV | reason=$REASON | operator=$(whoami)@$(hostname)" \
  >> .destroy-audit.log

echo "→ Step 1: Disabling protection..."
terraform -chdir=terraform apply -auto-approve \
  -var-file="terraform/environments/${ENV}.tfvars" \
  -var="enable_protection=false" 2>&1 | tail -10

echo "→ Step 2: Removing ArgoCD finalizers (prevents hang)..."
kubectl get applications -n argocd -o name | xargs -I{} \
  kubectl patch {} -n argocd \
  --type=json \
  -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true

echo "→ Step 3: Destroying..."
terraform -chdir=terraform destroy -auto-approve \
  -var-file="terraform/environments/${ENV}.tfvars" \
  -var="enable_protection=false" 2>&1 | tail -20

echo ""
echo "✓ Destroy complete. Audit entry written to .destroy-audit.log"
