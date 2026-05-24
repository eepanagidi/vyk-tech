#!/usr/bin/env bash
# Create k3d cluster from config file
set -euo pipefail

echo "→ Creating k3d cluster..."
k3d cluster create --config k3d-cluster.yaml

echo "→ Waiting for nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "→ Cluster nodes:"
kubectl get nodes -o wide

echo "✓ Cluster ready."
