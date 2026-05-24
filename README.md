# Vyking DevOps Platform — Senior Practical Task

A production-grade local Kubernetes platform demonstrating:
**Terraform → ArgoCD (App of Apps) → Helm → GitOps → MySQL + Backups**

---

## Architecture Overview

```
Git Repository
├── terraform/              ← Provisions ArgoCD + defines parent Applications
├── infrastructure/
│   ├── argocd-apps/        ← Child ArgoCD Applications (App of Apps pattern)
│   ├── mysql/              ← Bitnami MySQL values
│   └── backup/             ← CronJob, PVC, RBAC
└── applications/           ← Custom Helm chart: frontend + backend
```

### GitOps Flow

```
terraform apply
    └─▶ ArgoCD installed (Helm)
         └─▶ infrastructure App (monitors infrastructure/argocd-apps/)
              ├─▶ mysql App      → Bitnami MySQL + custom values
              └─▶ backup App     → PVC + CronJob + RBAC
         └─▶ applications App (monitors applications/)
              └─▶ Custom Helm chart → frontend + backend
```

### Security Highlights
- All containers run **non-root** with `readOnlyRootFilesystem: true`
- **Capabilities dropped** (`drop: ALL`) on every container
- **NetworkPolicies**: default-deny with explicit per-component allow rules
- **RBAC**: dedicated ServiceAccounts with minimum required permissions
- MySQL password sourced from **K8s Secret**, never hardcoded or in Git
- **PodDisruptionBudgets** protect minimum availability during node maintenance
- Seccomp profile `RuntimeDefault` on all pods

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| k3d | ≥ 5.6 | `brew install k3d` |
| kubectl | ≥ 1.28 | `brew install kubectl` |
| Terraform | ≥ 1.5 | `brew install terraform` |
| Git | any | — |

---

## Step-by-Step Setup

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/vyking-devops.git
cd vyking-devops
```

### 2. Inject Your Git Repository URL

This replaces the `GIT_REPO_URL` placeholder in ArgoCD child app manifests and creates `terraform/terraform.tfvars`:

```bash
./scripts/init.sh https://github.com/YOUR_USERNAME/vyking-devops
```

Commit and push the updated files:
```bash
git add infrastructure/argocd-apps/ terraform/terraform.tfvars
git commit -m "chore: inject git repo URL"
git push
```

### 3. Create the k3d Cluster

```bash
./scripts/create-cluster.sh
```

Verify:
```bash
kubectl get nodes -o wide
# Expected: 1x control-plane, 2x agent nodes — all Ready
```

### 4. Pre-create Secrets (not stored in Git)

```bash
./scripts/create-secrets.sh
```

This creates the `mysql-credentials` Secret and `mysql-initdb` ConfigMap in the `infrastructure` namespace.

### 5. Deploy Everything with Terraform

```bash
cd terraform
terraform init
terraform plan    # Review before applying
terraform apply
cd ..
```

Terraform will:
1. Create the `argocd` namespace
2. Install ArgoCD via Helm
3. Wait 45s for CRDs to register
4. Create the `infrastructure` and `applications` ArgoCD parent apps

---

## Verification

### Access the ArgoCD UI

```bash
# Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:80
```

Open http://localhost:8080 — login with `admin` and the password above.

You should see four Applications:
- `infrastructure` (parent) → Healthy/Synced
- `mysql` (child) → Healthy/Synced
- `backup` (child) → Healthy/Synced
- `applications` (parent+app) → Healthy/Synced

### Verify MySQL is Running

```bash
kubectl get pods -n infrastructure
# mysql-0 should be Running

# Connect to MySQL
kubectl exec -it -n infrastructure mysql-0 -- \
  mysql -u root -p"$(kubectl get secret mysql-credentials -n infrastructure \
    -o jsonpath='{.data.mysql-root-password}' | base64 -d)" appdb \
  -e "SELECT * FROM items;"
```

### Verify Backup CronJob

The CronJob runs every 5 minutes. After the first run:

```bash
# Check CronJob status
kubectl get cronjob -n infrastructure
kubectl get jobs -n infrastructure

# Check backup files inside the PVC
kubectl run backup-check --rm -it --restart=Never \
  --image=busybox \
  --overrides='{"spec":{"volumes":[{"name":"bk","persistentVolumeClaim":{"claimName":"mysql-backup-storage"}}],"containers":[{"name":"c","image":"busybox","command":["ls","-lh","/backups"],"volumeMounts":[{"name":"bk","mountPath":"/backups"}]}]}}' \
  -n infrastructure

# Expected output:
# appdb_20240115_143000.sql.gz   ...
# appdb_20240115_143500.sql.gz   ...
```

Or exec into a completed job pod:
```bash
LATEST_JOB=$(kubectl get jobs -n infrastructure -o name | tail -1)
POD=$(kubectl get pods -n infrastructure -l job-name=${LATEST_JOB##*/} -o name)
kubectl exec -n infrastructure $POD -- ls -lh /backups
```

### Verify Frontend → Backend Communication

```bash
# Port-forward to frontend
kubectl port-forward svc/frontend -n applications 3000:80

# In another terminal — confirm frontend proxies to backend
curl http://localhost:3000/api/
# Expected: "Hello from Vyking Backend!"

# Confirm frontend health
curl http://localhost:3000/healthz
# Expected: "ok"
```

### Verify Data Persistence

```bash
# Write data
kubectl exec -it -n infrastructure mysql-0 -- \
  mysql -u root -p"$(kubectl get secret mysql-credentials -n infrastructure \
    -o jsonpath='{.data.mysql-root-password}' | base64 -d)" appdb \
  -e "INSERT INTO items (name) VALUES ('persistence-test');"

# Delete and recreate the pod (simulates crash)
kubectl delete pod mysql-0 -n infrastructure
kubectl wait --for=condition=Ready pod/mysql-0 -n infrastructure --timeout=120s

# Verify data survived
kubectl exec -it -n infrastructure mysql-0 -- \
  mysql -u root -p"$(kubectl get secret mysql-credentials -n infrastructure \
    -o jsonpath='{.data.mysql-root-password}' | base64 -d)" appdb \
  -e "SELECT * FROM items WHERE name='persistence-test';"
```

---

## Making a GitOps Change

This demonstrates the GitOps workflow end-to-end:

```bash
# Example: scale backend to 3 replicas
# Edit applications/values.yaml → backend.replicaCount: 3
git add applications/values.yaml
git commit -m "feat: scale backend to 3 replicas"
git push
# ArgoCD detects the diff and syncs automatically (within ~3 min)
kubectl get pods -n applications -w
```

---

## Clean Up

```bash
./scripts/teardown.sh
```

This runs `terraform destroy` then deletes the k3d cluster. The backup PVC has `Delete=false` in ArgoCD sync options — to fully remove it:
```bash
kubectl delete pvc mysql-backup-storage -n infrastructure
```

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| App of Apps pattern | Terraform manages only the two parent apps; child apps are Git-managed, enabling GitOps for the GitOps config itself |
| Multi-source ArgoCD (MySQL) | Separates the upstream Bitnami chart from our custom values — chart updates don't require repo changes |
| Secrets pre-created outside GitOps | Secrets must never touch Git; script + operator/ESO is the production pattern |
| `maxUnavailable: 0` rolling update | Zero-downtime — always maintain full capacity during deploys |
| `topologySpreadConstraints` | Ensures pods don't co-locate on same node, surviving single-node failure |
| Backup retention in CronJob | Self-cleaning; keeps last 288 backups (~24h at 5-min cadence) without external tooling |

---

## Database Protection & Recovery

### How the DB is protected (5 layers)

| Layer | Mechanism | What it prevents |
|---|---|---|
| 1. StorageClass | `reclaimPolicy: Retain` | PV data survives PVC deletion |
| 2. PVC annotation | `helm.sh/resource-policy: keep` | PVC survives `helm uninstall` |
| 3. ArgoCD sync option | `Delete=false, Prune=false` | ArgoCD never removes PVC/StatefulSet |
| 4. Gatekeeper | `DeletionProtection` constraint | `kubectl delete` is blocked at API level |
| 5. ArgoCD app | `prune: false` on mysql app | Git removal doesn't trigger K8s deletion |

The Gatekeeper constraint uses `enforcementAction: warn` locally (so you can still tear down dev environments) and should be changed to `deny` in staging/production.

### Override procedure (intentional deletion)

```bash
# Step 1: Remove the protection annotation
kubectl annotate pvc data-mysql-0 -n infrastructure \
  vyking.io/deletion-override=true --overwrite

# Step 2: Delete (Gatekeeper now allows it)
kubectl delete pvc data-mysql-0 -n infrastructure

# Step 3: Remove the override (clean up)
# (resource is gone, but remove from any copies)
```

### Recovery after accidental PVC deletion

If `data-mysql-0` is deleted but the StorageClass used `Retain`, the PV still exists:

```bash
# 1. Find the Released PV (data is still there)
kubectl get pv | grep Released

# 2. Clear the claimRef so it becomes Available again
kubectl patch pv <pv-name> \
  -p '{"spec":{"claimRef": null}}'

# 3. Re-create the PVC pointing at that specific PV
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-mysql-0
  namespace: infrastructure
  annotations:
    helm.sh/resource-policy: keep
    argocd.argoproj.io/sync-options: "Delete=false,Prune=false"
    vyking.io/deletion-protected: "true"
spec:
  storageClassName: mysql-retain
  volumeName: <pv-name>      # Bind to the specific PV
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
EOF

# 4. MySQL StatefulSet will rebind automatically on next pod start
kubectl rollout restart statefulset/mysql -n infrastructure
```

### Recovery from backup

If the PV is also gone (worst case), restore from the backup CronJob files:

```bash
# 1. Find the latest backup on the backup PVC
kubectl run restore --rm -it --restart=Never \
  --image=bitnami/mysql:8.0.36 \
  --overrides='{
    "spec": {
      "tolerations": [{"key":"role","operator":"Equal","value":"worker","effect":"NoSchedule"}],
      "volumes": [{"name":"bk","persistentVolumeClaim":{"claimName":"mysql-backup-storage"}}],
      "containers": [{"name":"r","image":"bitnami/mysql:8.0.36",
        "command":["ls","-lt","/backups"],
        "volumeMounts":[{"name":"bk","mountPath":"/backups"}]}]
    }
  }' -n infrastructure

# 2. Restore the latest backup into a fresh MySQL
LATEST=appdb_20240523_143000.sql.gz   # Replace with actual filename
kubectl run restore --rm -it --restart=Never \
  --image=bitnami/mysql:8.0.36 \
  --overrides='{...same overrides...}' \
  -n infrastructure -- \
  sh -c "zcat /backups/$LATEST | mysql -h mysql -u root -p\$MYSQL_ROOT_PASSWORD appdb"
```
