#!/usr/bin/env bash
# ──────────────────────────────────────────────
# recover-db.sh — Database recovery procedures
#
# Use this script if:
#   - MySQL pod won't start (PVC issue)
#   - mysql-credentials Secret was accidentally deleted
#   - PVC was deleted but PV still exists (Retain policy)
#
# Usage:
#   ./scripts/recover-db.sh check       # Diagnose the situation
#   ./scripts/recover-db.sh pvc         # Recover PVC from retained PV
#   ./scripts/recover-db.sh secret      # Restore Secret from backup
# ──────────────────────────────────────────────
set -euo pipefail

CMD="${1:-check}"

case "$CMD" in

  # ── Diagnose ────────────────────────────────
  check)
    echo "=== MySQL Pod Status ==="
    kubectl get pod mysql-0 -n infrastructure 2>/dev/null || echo "Pod not found"

    echo ""
    echo "=== PVC Status ==="
    kubectl get pvc -n infrastructure 2>/dev/null

    echo ""
    echo "=== PV Status (look for Released state) ==="
    kubectl get pv 2>/dev/null | grep -E "mysql|NAME"

    echo ""
    echo "=== Secret Status ==="
    kubectl get secret mysql-credentials -n infrastructure 2>/dev/null \
      && echo "Secret exists ✓" || echo "Secret MISSING ✗"

    echo ""
    echo "=== Recent Events ==="
    kubectl get events -n infrastructure --sort-by='.lastTimestamp' 2>/dev/null | tail -10
    ;;

  # ── Recover PVC from retained PV ────────────
  # If the PVC was deleted but the Retain policy saved the PV:
  pvc)
    echo "=== Finding Released PVs ==="
    RELEASED_PV=$(kubectl get pv -o json | \
      python3 -c "
import sys, json
pvs = json.load(sys.stdin)['items']
for pv in pvs:
    if pv.get('status',{}).get('phase') == 'Released':
        cap = pv['spec']['capacity']['storage']
        name = pv['metadata']['name']
        print(f'{name}  ({cap})')
")
    if [[ -z "$RELEASED_PV" ]]; then
      echo "No Released PVs found."
      echo "If the PV was also deleted, restore from the most recent backup:"
      echo "  kubectl exec -n infrastructure mysql-0 -- \\"
      echo "    mysql -u root -p appdb < /path/to/backup.sql"
      exit 1
    fi

    echo "Released PVs found:"
    echo "$RELEASED_PV"
    echo ""
    read -rp "Enter PV name to rebind: " PV_NAME

    echo "→ Clearing claimRef from PV (makes it Available again)..."
    kubectl patch pv "$PV_NAME" \
      -p '{"spec":{"claimRef": null}}'

    echo "→ Recreating PVC bound to this PV..."
    kubectl apply -f - << MANIFEST
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-mysql-0
  namespace: infrastructure
  annotations:
    helm.sh/resource-policy: keep
    argocd.argoproj.io/sync-options: Delete=false
    vyking.io/deletion-protected: "true"
    vyking.io/recovered-from: "$PV_NAME"
    vyking.io/recovery-timestamp: "$(date -u)"
spec:
  storageClassName: mysql-retain
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
  volumeName: $PV_NAME   # Bind directly to the retained PV
MANIFEST

    echo "✓ PVC rebound. Restart MySQL:"
    echo "  kubectl rollout restart statefulset/mysql -n infrastructure"
    ;;

  # ── Restore Secret from backup ───────────────
  # If the credentials Secret was deleted:
  secret)
    echo "MySQL credentials Secret recovery:"
    echo ""
    echo "Option 1 — Restore from SOPS-encrypted backup in Git:"
    echo "  sops --decrypt secrets/mysql-credentials.enc.yaml | kubectl apply -f -"
    echo ""
    echo "Option 2 — If you know the passwords:"
    read -rp "  Root password: " ROOT_PASS
    read -rp "  App password:  " APP_PASS

    kubectl create secret generic mysql-credentials \
      --namespace infrastructure \
      --from-literal=mysql-root-password="$ROOT_PASS" \
      --from-literal=mysql-password="$APP_PASS" \
      --from-literal=mysql-replication-password="$APP_PASS" \
      --dry-run=client -o yaml | kubectl apply -f -

    kubectl annotate secret mysql-credentials \
      --namespace infrastructure --overwrite \
      "vyking.io/deletion-protected=true" \
      "vyking.io/contains-stateful-data=true" \
      "vyking.io/recovered-at=$(date -u)"

    echo "✓ Secret restored. Restart MySQL:"
    echo "  kubectl rollout restart statefulset/mysql -n infrastructure"
    ;;

  *)
    echo "Usage: $0 [check|pvc|secret]"
    exit 1
    ;;
esac
