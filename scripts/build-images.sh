#!/usr/bin/env bash
# ──────────────────────────────────────────────
# build-images.sh — Build the frontend + backend images and import them into
# the k3d cluster, so the Helm chart can run them with imagePullPolicy:
# IfNotPresent without any external container registry.
#
# Run AFTER the cluster exists (scripts/create-cluster.sh) and BEFORE
# `terraform apply`. Re-run after code changes, then restart the rollout.
# ──────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER="${K3D_CLUSTER:-vyking-cluster}"
TAG="${IMAGE_TAG:-0.1.0}"
BACKEND_IMAGE="vyking-backend:${TAG}"
FRONTEND_IMAGE="vyking-frontend:${TAG}"

echo "→ Building ${BACKEND_IMAGE} (backend/) ..."
docker build -t "${BACKEND_IMAGE}" ./backend

echo "→ Building ${FRONTEND_IMAGE} (frontend/) ..."
docker build -t "${FRONTEND_IMAGE}" ./frontend

echo "→ Importing images into k3d cluster '${CLUSTER}' ..."
k3d image import "${BACKEND_IMAGE}" "${FRONTEND_IMAGE}" -c "${CLUSTER}"

echo "✓ Images built and imported:"
echo "    ${BACKEND_IMAGE}"
echo "    ${FRONTEND_IMAGE}"
echo "  (referenced by applications/values.yaml — keep the tag in sync)"
