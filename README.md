# Vyking DevOps Platform — Senior Practical Task

A production-grade local Kubernetes platform demonstrating:
**Terraform → ArgoCD (App of Apps) → Helm → GitOps → MySQL + Backups**

---

## Architecture Overview

```
Git Repository
├── terraform/              ← Installs ArgoCD + ingress-nginx (Helm), defines 2 parent Apps + AppProjects
├── infrastructure/
│   ├── argocd-apps/        ← Child ArgoCD Applications (App of Apps pattern)
│   ├── base/              ← StorageClass (Retain) + MySQL RBAC (ServiceAccount/Role/RoleBinding)
│   ├── mysql/              ← Bitnami MySQL values
│   ├── backup/             ← CronJob + PVC
│   ├── gatekeeper/        ← OPA Gatekeeper DeletionProtection ConstraintTemplate
│   └── gatekeeper-policies/ ← The Constraints (which resources are protected)
└── applications/           ← Custom Helm chart: frontend + backend
```

### GitOps Flow

`terraform apply` installs ArgoCD, then the App-of-Apps tree converges (sync-waves
in parentheses keep ordering correct — e.g. the StorageClass exists before MySQL
claims it, the Gatekeeper CRD exists before its Constraints):

```
terraform apply
    ├─▶ ArgoCD installed (Helm)            +  ingress-nginx installed (Helm)
    └─▶ infrastructure-local  (parent App, watches infrastructure/argocd-apps/)
         ├─▶ platform-base        (wave -2) → StorageClass (Retain) + MySQL RBAC
         ├─▶ gatekeeper           (wave  0) → OPA controller + ConstraintTemplate
         ├─▶ gatekeeper-policies  (wave  1) → DeletionProtection Constraints
         ├─▶ mysql                (wave  0) → Bitnami MySQL (multi-source: chart + our values)
         └─▶ backup               (wave  0) → backup PVC + every-5-min CronJob
    └─▶ applications-local    (parent App, watches applications/)
         └─▶ Custom Helm chart → frontend + backend (+ HPA, Ingress, NetworkPolicies)
```

Resource names carry the environment suffix (e.g. `backend-local`, `mysql`,
`infrastructure-local`) — set by the `environment` Terraform variable (default `local`).

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
| Docker | running daemon | Docker Desktop / `brew install --cask docker` — **required** by k3d and for building the app images |
| k3d | ≥ 5.6 | `brew install k3d` |
| kubectl | ≥ 1.28 | `brew install kubectl` |
| Terraform | ≥ 1.5 | `brew install terraform` |
| Git | any | — |
| argocd CLI | optional | `brew install argocd` — only needed to drive syncs from the terminal; the UI works without it |

> Helm is **not** required as a separate tool — Terraform's Helm provider installs the charts.

> **Private repo?** ArgoCD needs a credential to fetch it. Create a fine-grained GitHub PAT
> (Contents: Read) and put it in `terraform/secret.auto.tfvars` (git-ignored):
> ```hcl
> github_token = "github_pat_..."
> git_username = "git"
> ```
> Public repos need none of this.

---

## Step-by-Step Setup

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/vyk-tech.git
cd vyk-tech
```

### 2. Inject Your Git Repository URL + Branch

ArgoCD pulls the child app manifests from *your* repo, so the URL and branch must
be injected. `init.sh` rewrites the `repoURL`/`targetRevision` in the ArgoCD child
apps and writes `terraform/terraform.tfvars` (git-ignored). It is idempotent — safe
to re-run for a different repo/branch.

```bash
./scripts/init.sh https://github.com/YOUR_USERNAME/vyk-tech.git <branch>
```

ArgoCD can only sync commits that are pushed, so commit and push the injected
manifests to that branch:
```bash
git add infrastructure/argocd-apps/
git commit -m "chore: inject git repo URL"
git push origin <branch>
```
> `terraform/terraform.tfvars` is git-ignored on purpose — don't commit it.

### 3. Create the k3d Cluster

```bash
./scripts/create-cluster.sh
```

Verify:
```bash
kubectl get nodes -o wide
# Expected: 1x control-plane (server), 2x agent (worker) nodes — all Ready
```

### 4. Build & Import the App Images

The frontend/backend run from locally-built images imported straight into k3d (no
external registry). **Skip this and the app pods will `ImagePullBackOff`.**

```bash
./scripts/build-images.sh        # builds vyking-backend:0.1.0 + vyking-frontend:0.1.0, imports both into k3d
```

### 5. Pre-create Secrets (not stored in Git)

```bash
./scripts/create-secrets.sh      # add --random for generated passwords
```

This creates the `infrastructure` + `applications` namespaces (with baseline Pod
Security), the `mysql-credentials` Secret, and the `mysql-initdb` ConfigMap (from
`scripts/init.sql`).

### 6. Deploy Everything with Terraform

```bash
cd terraform
terraform init
terraform plan    # Review before applying
terraform apply   # ~3-5 min: installs ArgoCD + ingress-nginx, then ArgoCD converges the App-of-Apps tree
cd ..
```

Terraform will:
1. Create the `argocd` namespace and install ArgoCD via Helm
2. Install ingress-nginx (Helm)
3. Create the two AppProjects + parent Applications (`infrastructure-local`, `applications-local`)
4. (Private repo) create the ArgoCD repository credential from your PAT

ArgoCD then syncs the child apps automatically. Watch them go Healthy/Synced:
```bash
kubectl get applications -n argocd -w
```

---

## Verification

### Access the ArgoCD UI

```bash
# Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Port-forward (8080 is taken by the k3d load-balancer → use 8085)
kubectl port-forward svc/vyking-platform-local-argocd-server -n argocd 8085:80
```

Open http://localhost:8085 — login with `admin` and the password above.

You should see **seven** Applications, all Healthy/Synced:
- `infrastructure-local` (parent) — App-of-Apps for the infra side
- `applications-local` (parent) — frontend + backend chart
- `platform-base` — StorageClass + MySQL RBAC
- `gatekeeper` — OPA controller + ConstraintTemplate
- `gatekeeper-policies` — DeletionProtection Constraints
- `mysql` — Bitnami MySQL
- `backup` — backup PVC + CronJob

```bash
kubectl get applications -n argocd
```

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

# Check backup files inside the PVC. The PVC lives on a worker node, so the
# inspect pod needs the same toleration + nodeSelector as the backup job.
kubectl run backup-check --rm -it --restart=Never \
  --image=busybox \
  --overrides='{"spec":{"tolerations":[{"key":"role","operator":"Equal","value":"worker","effect":"NoSchedule"}],"nodeSelector":{"role":"worker"},"volumes":[{"name":"bk","persistentVolumeClaim":{"claimName":"mysql-backup-storage"}}],"containers":[{"name":"c","image":"busybox","command":["ls","-lh","/backups"],"volumeMounts":[{"name":"bk","mountPath":"/backups"}]}]}}' \
  -n infrastructure

# Expected output:
# appdb_20260524_143000.sql.gz   ...
# appdb_20260524_143500.sql.gz   ...
```

Or exec into a completed job pod:
```bash
LATEST_JOB=$(kubectl get jobs -n infrastructure -o name | tail -1)
POD=$(kubectl get pods -n infrastructure -l job-name=${LATEST_JOB##*/} -o name)
kubectl exec -n infrastructure $POD -- ls -lh /backups
```

### Verify Frontend → Backend Communication

```bash
# Port-forward to frontend (avoid 8080 — that's the k3d load-balancer)
kubectl port-forward svc/frontend-local -n applications 3000:80

# In another terminal — frontend nginx proxies /api/* to the backend (strips /api)
curl http://localhost:3000/api/
# Expected: "Hello from Vyking Backend!"

curl http://localhost:3000/api/health
# Expected: {"status":"ok","database":"ok"}   ← backend reached MySQL

curl http://localhost:3000/api/items
# Expected: JSON array with seed-item-1 / seed-item-2

# Frontend's own liveness endpoint
curl http://localhost:3000/healthz
# Expected: "ok"
```

You can also reach it through the Ingress (k3d maps host 8080 → ingress :80):
```bash
echo "127.0.0.1 vyking.local api.vyking.local" | sudo tee -a /etc/hosts
curl http://vyking.local:8080/            # frontend UI
curl http://api.vyking.local:8080/health  # backend via ingress
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
# Example: scale the FRONTEND to 3 replicas.
# (Use frontend, not backend — the backend has an HPA, so its replica count is
#  controlled by the autoscaler and `replicaCount` is intentionally ignored.)
# Edit applications/values.yaml → frontend.replicaCount: 3
git add applications/values.yaml
git commit -m "feat: scale frontend to 3 replicas"
git push origin <branch>
# ArgoCD polls git (~3 min) and syncs automatically — or force it:
#   argocd app sync applications-local   (refresh-then-sync; a bare sync can race the git fetch)
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
| 4. Gatekeeper | `DeletionProtection` constraint | `kubectl delete` on a protected resource is rejected at admission (in `deny`) |
| 5. ArgoCD app | `prune: false` on mysql app | Git removal doesn't trigger K8s deletion |

**Gatekeeper enforcement mode.** The constraints ship as `enforcementAction: warn`
locally — a `kubectl delete` on a protected PVC/Secret/StatefulSet still succeeds but
prints a Gatekeeper warning, so `terraform destroy`/teardown isn't blocked. Set them
to `deny` for staging/production, where the same delete is **rejected**:

```
$ kubectl delete secret mysql-credentials -n infrastructure
Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied
the request: [protect-db-secrets] Resource Secret/mysql-credentials is deletion-protected.
```

For this to fire on deletes, the Gatekeeper webhook is configured with
`enableDeleteOperations: true` (it defaults to CREATE/UPDATE only) and the rego matches
on `oldObject` (the object under review on a DELETE). Layers 1-3 + 5 protect the data
regardless of Gatekeeper's mode — the PV `Retain` policy is the real backstop.

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

# Uses the official `mysql:8.0.36` image (the `bitnami/mysql` Docker Hub tags were
# retired in 2025 — the same reason the backup CronJob uses the official image).
```bash
# 1. Find the latest backup on the backup PVC (worker toleration + nodeSelector
#    so the pod can mount the worker-bound PVC)
kubectl run restore --rm -it --restart=Never \
  --image=mysql:8.0.36 \
  --overrides='{
    "spec": {
      "tolerations": [{"key":"role","operator":"Equal","value":"worker","effect":"NoSchedule"}],
      "nodeSelector": {"role":"worker"},
      "volumes": [{"name":"bk","persistentVolumeClaim":{"claimName":"mysql-backup-storage"}}],
      "containers": [{"name":"r","image":"mysql:8.0.36",
        "command":["ls","-lt","/backups"],
        "volumeMounts":[{"name":"bk","mountPath":"/backups"}]}]
    }
  }' -n infrastructure

# 2. Restore the latest backup into the running MySQL (service: mysql.infrastructure)
LATEST=appdb_20260524_143000.sql.gz   # Replace with actual filename from step 1
kubectl run restore --rm -it --restart=Never \
  --image=mysql:8.0.36 \
  --overrides='{
    "spec": {
      "tolerations": [{"key":"role","operator":"Equal","value":"worker","effect":"NoSchedule"}],
      "nodeSelector": {"role":"worker"},
      "volumes": [{"name":"bk","persistentVolumeClaim":{"claimName":"mysql-backup-storage"}}],
      "containers": [{"name":"r","image":"mysql:8.0.36",
        "command":["sh","-c","zcat /backups/'"$LATEST"' | mysql -h mysql -u root -p\"$MYSQL_ROOT_PASSWORD\" appdb"],
        "env":[{"name":"MYSQL_ROOT_PASSWORD","valueFrom":{"secretKeyRef":{"name":"mysql-credentials","key":"mysql-root-password"}}}],
        "volumeMounts":[{"name":"bk","mountPath":"/backups"}]}]
    }
  }' -n infrastructure
```
