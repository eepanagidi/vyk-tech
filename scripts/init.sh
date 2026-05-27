#!/usr/bin/env bash
# ──────────────────────────────────────────────
# init.sh — One-shot bootstrap: generate terraform/terraform.tfvars (git-ignored)
# with the Git repo URL + branch to deploy from.
#
# The App-of-Apps child Applications are rendered from a Helm chart
# (infrastructure/argocd-apps); the parent Application passes repoURL and
# targetRevision to that chart as Helm parameters (Terraform reads them from these
# tfvars). Nothing about the repo or branch is baked into a committed manifest, so
# deploying a different branch is just a different tfvars value — no file rewrite,
# no commit. The branch only needs to be pushed so ArgoCD can fetch it.
#
# Usage: ./scripts/init.sh <git-repo-url> [branch]
#   ./scripts/init.sh https://github.com/you/vyk-tech.git master
# ──────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_URL="${1:-}"
BRANCH="${2:-master}"
if [[ -z "$REPO_URL" ]]; then
  echo "Usage: $0 <git-repo-url> [branch]"
  echo "Example: $0 https://github.com/you/vyk-tech.git master"
  exit 1
fi

echo "→ Writing terraform/terraform.tfvars (repo '${REPO_URL}', branch '${BRANCH}') ..."
cat > terraform/terraform.tfvars <<TFVARS
git_repo_url      = "${REPO_URL}"
git_repo_revision = "${BRANCH}"
TFVARS

echo "✓ Done. Next steps:"
echo "    ./scripts/create-cluster.sh"
echo "    ./scripts/build-images.sh"
echo "    ./scripts/create-secrets.sh"
echo "    (cd terraform && terraform init && terraform apply)"
