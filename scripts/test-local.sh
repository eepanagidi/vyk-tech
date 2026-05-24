#!/usr/bin/env bash
# ──────────────────────────────────────────────
# test-local.sh — Full local integration test
#
# Three modes:
#   ./scripts/test-local.sh compose   # Docker Compose only (fast, no K8s)
#   ./scripts/test-local.sh k8s       # Full k3d cluster
#   ./scripts/test-local.sh all       # Both
# ──────────────────────────────────────────────
set -euo pipefail

MODE="${1:-compose}"
PASS=0; FAIL=0

ok()   { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
header() { echo ""; echo "── $* ──────────────────────────────────"; }

# ══════════════════════════════════════════════
# LAYER 1: Docker Compose (backend + MySQL)
# No K8s needed — tests real Go API + DB
# ══════════════════════════════════════════════
test_compose() {
  echo ""
  echo "══════════════════════════════════════"
  echo " Layer 1: Docker Compose"
  echo "══════════════════════════════════════"

  docker compose up -d --build --wait 2>&1 | tail -5

  header "Health check"
  HEALTH=$(curl -sf http://localhost:8080/health)
  echo "$HEALTH" | grep -q '"status":"ok"'    && ok "status=ok"    || fail "status not ok"
  echo "$HEALTH" | grep -q '"database":"ok"'  && ok "database=ok"  || fail "database not ok"

  header "Seed data"
  curl -sf http://localhost:8080/items | grep -q "seed-item-1" \
    && ok "seed data present" || fail "seed data missing"

  header "CRUD operations"
  CREATED=$(curl -sf -X POST http://localhost:8080/items \
    -H "Content-Type: application/json" -d '{"name":"local-test"}')
  echo "$CREATED" | grep -q '"id":'      && ok "POST /items" || fail "POST /items failed"
  ID=$(echo "$CREATED" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

  curl -sf http://localhost:8080/items/$ID | grep -q "local-test" \
    && ok "GET /items/$ID" || fail "GET /items/$ID failed"

  curl -sf -X DELETE http://localhost:8080/items/$ID
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/items/$ID)
  [ "$STATUS" = "404" ] && ok "DELETE → 404" || fail "DELETE returned $STATUS"

  header "Frontend"
  FE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/)
  [ "$FE" = "200" ] && ok "Frontend HTTP 200" || fail "Frontend returned $FE"

  header "Persistence across container restart"
  curl -sf -X POST http://localhost:8080/items \
    -H "Content-Type: application/json" -d '{"name":"persist-test"}' > /dev/null
  docker compose restart mysql 2>/dev/null
  sleep 10
  docker compose restart backend 2>/dev/null
  sleep 5
  curl -sf http://localhost:8080/items | grep -q "persist-test" \
    && ok "Data survived container restart" || fail "Data lost after restart"

  docker compose down -v 2>/dev/null
  echo ""
  echo " Compose results: $PASS passed, $FAIL failed"
}

# ══════════════════════════════════════════════
# LAYER 2: Full k3d cluster
# ══════════════════════════════════════════════
test_k8s() {
  echo ""
  echo "══════════════════════════════════════"
  echo " Layer 2: k3d Cluster"
  echo "══════════════════════════════════════"

  header "Creating cluster"
  k3d cluster create --config k3d-cluster.yaml
  kubectl wait --for=condition=Ready nodes --all --timeout=120s
  ok "3 nodes Ready"

  header "Worker taints"
  TAINTED=$(kubectl get nodes -o json | \
    python3 -c "
import sys,json
nodes=json.load(sys.stdin)['items']
count=sum(1 for n in nodes
  for t in (n.get('spec',{}).get('taints') or [])
  if t.get('key')=='role' and t.get('value')=='worker')
print(count)")
  [ "$TAINTED" -ge 2 ] && ok "Worker nodes tainted ($TAINTED)" || fail "Expected 2+ taints, got $TAINTED"

  header "Secrets"
  ./scripts/create-secrets.sh --random 2>&1 | tail -3
  ok "Secrets created"

  header "Terraform apply"
  cd terraform
  terraform init -backend=false -no-color 2>&1 | tail -2
  terraform apply -auto-approve -no-color \
    -var="git_repo_url=https://github.com/YOUR_USERNAME/vyking-devops" \
    -var="environment=local" 2>&1 | tail -10
  cd ..
  ok "Terraform apply complete"

  header "ArgoCD ready"
  kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
  ok "ArgoCD server running"

  header "Wait for workloads"
  kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=backend-local \
    -n applications --timeout=300s 2>/dev/null \
    && ok "Backend pods ready" || fail "Backend pods not ready"
  kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=frontend-local \
    -n applications --timeout=120s 2>/dev/null \
    && ok "Frontend pods ready" || fail "Frontend pods not ready"
  kubectl wait --for=condition=Ready pod/mysql-0 -n infrastructure --timeout=180s \
    && ok "MySQL pod ready" || fail "MySQL not ready"

  header "Pods on worker nodes"
  CONTROL=$(kubectl get nodes --selector=node-role.kubernetes.io/control-plane \
    -o jsonpath='{.items[0].metadata.name}')
  MISPLACED=$(kubectl get pods -n applications -o json | \
    python3 -c "
import sys,json
pods=json.load(sys.stdin)['items']
print(sum(1 for p in pods if p.get('spec',{}).get('nodeName')=='$CONTROL'))")
  [ "$MISPLACED" -eq 0 ] \
    && ok "All app pods on workers (none on control-plane)" \
    || fail "Found $MISPLACED pods on control-plane"

  header "Resource limits"
  for deploy in backend-local frontend-local; do
    LIMITS=$(kubectl get deployment/$deploy -n applications \
      -o jsonpath='{.spec.template.spec.containers[0].resources.limits}')
    [ -n "$LIMITS" ] && ok "$deploy has resource limits" || fail "$deploy missing limits"
  done

  header "Probes"
  for deploy in backend-local frontend-local; do
    L=$(kubectl get deployment/$deploy -n applications \
      -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}')
    R=$(kubectl get deployment/$deploy -n applications \
      -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}')
    [ -n "$L" ] && [ -n "$R" ] \
      && ok "$deploy has liveness + readiness probes" \
      || fail "$deploy missing probes"
  done

  header "Backend API (port-forward)"
  kubectl port-forward svc/backend-local -n applications 8082:80 &
  PF_PID=$!
  sleep 5

  HEALTH=$(curl -sf http://localhost:8082/health 2>/dev/null || echo "")
  echo "$HEALTH" | grep -q '"database":"ok"' \
    && ok "Backend /health → DB connected" || fail "Backend health failed: $HEALTH"

  ITEMS=$(curl -sf http://localhost:8082/items 2>/dev/null || echo "")
  echo "$ITEMS" | grep -q "seed-item-1" \
    && ok "GET /items returns seed data" || fail "GET /items failed"

  CREATED=$(curl -sf -X POST http://localhost:8082/items \
    -H "Content-Type: application/json" -d '{"name":"k8s-test"}' 2>/dev/null || echo "")
  echo "$CREATED" | grep -q '"id"' \
    && ok "POST /items works" || fail "POST /items failed"
  kill $PF_PID 2>/dev/null || true

  header "MySQL persistence"
  MYSQL_ROOT=$(kubectl get secret mysql-credentials -n infrastructure \
    -o jsonpath='{.data.mysql-root-password}' | base64 -d)
  kubectl exec -n infrastructure mysql-0 -- \
    mysql -u root -p"$MYSQL_ROOT" appdb -e "INSERT INTO items (name) VALUES ('pod-restart-test');" 2>/dev/null
  kubectl delete pod mysql-0 -n infrastructure
  kubectl wait --for=condition=Ready pod/mysql-0 -n infrastructure --timeout=120s
  kubectl exec -n infrastructure mysql-0 -- \
    mysql -u root -p"$MYSQL_ROOT" appdb \
    -e "SELECT name FROM items WHERE name='pod-restart-test';" 2>/dev/null | grep -q "pod-restart-test" \
    && ok "Data persists across pod restart" || fail "Data lost after pod restart"

  header "Backup CronJob"
  kubectl create job --from=cronjob/mysql-backup manual-test -n infrastructure 2>/dev/null
  kubectl wait --for=condition=complete job/manual-test -n infrastructure --timeout=120s \
    && ok "Backup job completed" || fail "Backup job failed"

  header "Ingress"
  echo "127.0.0.1 vyking.local api.vyking.local" | sudo tee -a /etc/hosts > /dev/null
  sleep 5
  FE=$(curl -s -o /dev/null -w "%{http_code}" http://vyking.local:8080/ 2>/dev/null)
  [ "$FE" = "200" ] && ok "Frontend ingress HTTP 200" || fail "Frontend ingress returned $FE"
  API=$(curl -sf http://api.vyking.local:8080/health 2>/dev/null || echo "")
  echo "$API" | grep -q '"status":"ok"' \
    && ok "Backend API ingress OK" || fail "Backend API ingress failed"

  header "Teardown"
  k3d cluster delete vyking-cluster
  ok "Cluster deleted"

  echo ""
  echo " k8s results: $PASS passed, $FAIL failed"
}

# ══════════════════════════════════════════════
# Run selected mode
# ══════════════════════════════════════════════
case "$MODE" in
  compose) test_compose ;;
  k8s)     test_k8s ;;
  all)     test_compose; test_k8s ;;
  *) echo "Usage: $0 [compose|k8s|all]"; exit 1 ;;
esac

echo ""
echo "══════════════════════════════════════"
echo " Final: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
