#!/usr/bin/env bash
# ──────────────────────────────────────────────
# init.sh — One-shot bootstrap:
#   1. Inject the Git repo URL + branch into the ArgoCD child app manifests
#   2. Generate terraform/terraform.tfvars (git-ignored)
#
# Usage: ./scripts/init.sh <git-repo-url> [branch]
#   ./scripts/init.sh https://github.com/you/vyk-tech.git platform
# ──────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_URL="${1:-}"
BRANCH="${2:-main}"
if [[ -z "$REPO_URL" ]]; then
  echo "Usage: $0 <git-repo-url> [branch]"
  echo "Example: $0 https://github.com/you/vyk-tech.git platform"
  exit 1
fi

# Portable in-place sed (GNU on Linux/CI, BSD on macOS)
sedi() {
  if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi
}

echo "→ Injecting repo URL '${REPO_URL}' (branch '${BRANCH}') into ArgoCD child apps ..."
while IFS= read -r -d '' f; do
  sedi "s|GIT_REPO_URL|${REPO_URL}|g" "$f"
  sedi "s|targetRevision: main|targetRevision: ${BRANCH}|g" "$f"
done < <(find infrastructure/argocd-apps -name '*.yaml' -print0)

echo "→ Writing terraform/terraform.tfvars ..."
cat > terraform/terraform.tfvars <<TFVARS
git_repo_url      = "${REPO_URL}"
git_repo_revision = "${BRANCH}"
TFVARS

echo "✓ Done. Next steps:"
echo "    git add -A && git commit -m 'chore: inject repo URL' && git push -u origin ${BRANCH}"
echo "    ./scripts/create-cluster.sh"
echo "    ./scripts/build-images.sh"
echo "    ./scripts/create-secrets.sh"
echo "    (cd terraform && terraform init && terraform apply)"
