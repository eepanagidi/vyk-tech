#!/usr/bin/env bash
# Full environment teardown
set -uo pipefail
cd "$(dirname "$0")/.."

echo "→ Destroying Terraform resources..."
( cd terraform && terraform destroy -auto-approve ) || echo "⚠ terraform destroy failed/partial — continuing to delete the cluster."

echo "→ Deleting k3d cluster (removes everything regardless)..."
k3d cluster delete vyking-cluster || true

echo "✓ Environment fully torn down."
