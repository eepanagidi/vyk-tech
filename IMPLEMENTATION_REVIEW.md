# Vyking DevOps Platform — Implementation Review

> A reviewer-facing companion to the task brief and `README.md`. It maps every task
> requirement to its implementation, lists the extras, catalogs security/performance
> features, records the tests run and their results, and proposes the next improvements
> (incl. the logging/metrics stack). Last verified: **2026-05-25**.

---

## 1. Current status at a glance

- **Stack:** local k3d (1 server + 2 workers, k3s v1.29.4, arm64) → Terraform installs ArgoCD + ingress-nginx → ArgoCD App-of-Apps → Helm (custom app chart + Bitnami MySQL) → MySQL + 5-min backup CronJob.
- **Health:** all **7 ArgoCD apps Synced/Healthy**; full app path (frontend → `/api` → backend → MySQL) works; backups flowing; data persists across pod and full-cluster restart.
- **Gates:** terraform validate + `plan` (no changes), tflint, helm lint, kubeconform (20/20), conftest/OPA, checkov, trivy, go vet/build — **all green**.
- **Git:** repo `github.com/eepanagidi/vyk-tech` (private), working branch `platform`, protected `master`.
  - **PR #1 (full platform) — MERGED to master.**
  - **PR #2 (open):** commits `a8b23f7` (static-gate fixes) + `fbd8230` (Go 1.26 bump) — ready to merge.
- **Cluster** is left running for review (`./scripts/teardown.sh` to tear down).

---

## 2. Architecture

```
Terraform (terraform/)
  ├─ helm_release.argocd            ArgoCD install (hardened values)
  ├─ helm_release.ingress_nginx     Ingress controller
  ├─ kubectl_manifest AppProjects   infrastructure-local / applications-local (RBAC scoping)
  └─ kubectl_manifest Applications  the 2 parent App-of-Apps roots
        │
        ├─ infrastructure-local  → infrastructure/argocd-apps/*
        │     ├─ platform-base        (wave -2)  StorageClass(Retain) + MySQL RBAC
        │     ├─ gatekeeper           (wave  0)  OPA controller + ConstraintTemplate
        │     ├─ gatekeeper-policies  (wave  1)  DeletionProtection Constraints
        │     ├─ mysql                (wave  0)  Bitnami MySQL (chart + our values)
        │     └─ backup               (wave  0)  backup PVC + every-5-min CronJob
        └─ applications-local    → applications/  (one Helm chart: frontend + backend)
```

Providers: `hashicorp/helm`, `hashicorp/kubernetes`, `gavinbunney/kubectl` (applies CRs without the CRD existing at plan time — solves the ArgoCD bootstrap), `hashicorp/time`.

---

## 3. Task requirements — coverage

| # | Requirement | Implementation | Status |
|---|---|---|---|
| 1 | Multi-node cluster: 1 control-plane + ≥2 workers | `k3d-cluster.yaml`: `servers: 1`, `agents: 2`; workers labeled `role=worker` + tainted `role=worker:NoSchedule` | ✅ |
| 2 | Terraform installs ArgoCD via Helm provider | `terraform/main.tf` `helm_release.argocd` + `argocd-values.yaml` | ✅ |
| 3 | Terraform defines 2 ArgoCD Applications | `terraform/argocd-apps.tf`: `infrastructure-local`, `applications-local` (as `kubectl_manifest`) | ✅ |
| 4 | App-of-Apps pattern | The 2 parents are Terraform-managed; child apps (`infrastructure/argocd-apps/*`) are Git-managed | ✅ |
| 5 | `applications/` = single custom Helm chart, frontend + backend | `applications/` chart renders both; backend = Go items API, frontend = nginx + static page proxying `/api` | ✅ |
| 6 | `infrastructure/` = Bitnami MySQL + backup CronJob | `infrastructure/mysql/values.yaml` (Bitnami chart, multi-source), `infrastructure/backup/` | ✅ |
| 7 | Backup: every 5 min | `cronjob.yaml` `schedule: "*/5 * * * *"` | ✅ |
| 8 | Backup: `mysqldump`, timestamped file | `appdb_$(date +%Y%m%d_%H%M%S).sql.gz` | ✅ |
| 9 | Backup: password from a K8s Secret | `secretKeyRef` → `mysql-credentials`; passed via `--defaults-extra-file` (not argv) | ✅ |
| 10 | Backup: separate PVC | `mysql-backup-storage` PVC, distinct from the MySQL data PVC | ✅ |
| 11 | Comprehensive README | `README.md` — every documented command verified to work | ✅ |
| 12 | `terraform/`, `infrastructure/`, `applications/` layout | Present as specified | ✅ |

---

## 4. Extras (beyond the brief)

- **OPA Gatekeeper deletion-protection** — `ConstraintTemplate` + 4 `Constraints` (PVCs, DB Secrets, StatefulSets, the MySQL ArgoCD Application). Blocks `kubectl delete` on annotated resources at admission (verified — see §7), with a documented override annotation.
- **Ingress-nginx** — host-based routing for the frontend (`vyking.local`); the backend has no public ingress (reached via the frontend `/api` proxy, NetworkPolicy-enforced frontend-only). Hardened securityContext.
- **Horizontal Pod Autoscaler** — backend, min 2 / max 6, CPU 70% / mem 80%.
- **NetworkPolicies** — default-deny + explicit per-component allow (`applications/templates/networkpolicy.yaml`).
- **PodDisruptionBudgets** — frontend + backend (`poddisruptionbudget.yaml`).
- **Multi-environment** — `environment` Terraform var drives resource naming + AppProject names + protection rules (local/staging/production).
- **CI/CD** — `ci.yaml` (terraform/helm/go lint + security + OPA policy + image build/push) and `integration.yaml` (full k3d e2e).
- **Static security gates** — checkov (IaC), tflint, conftest/OPA (`policy/`), trivy (image CVEs), kubeconform, shellcheck.
- **ArgoCD RBAC** — default-deny with named roles (`platform-admin` / `deployer` / `viewer`).
- **Layered DB durability** — PV `reclaimPolicy: Retain` + `helm.sh/resource-policy: keep` + ArgoCD `Delete=false`/`prune:false` + Gatekeeper + backups.
- **DB recovery** — documented PV-reclaim and backup-restore procedures (`README.md`, `scripts/recover-db.sh`).
- **Idempotent bootstrap** — `init.sh` re-injects repo URL/branch safely (GitHub URLs + branch revisions only; leaves Helm chart repos/versions untouched).
- **Hardened image** — distroless static, non-root, multi-arch (`TARGETARCH`), Go 1.26 (patched stdlib).

---

## 5. Security features

| Area | Control |
|---|---|
| Containers | `runAsNonRoot`, `readOnlyRootFilesystem` (where the workload allows), `drop: [ALL]` capabilities, `seccompProfile: RuntimeDefault` |
| Backend image | Distroless `static:nonroot`, static CGO-free binary, Go 1.26 stdlib (0 HIGH/CRITICAL in trivy) |
| Secrets | Sourced from K8s Secrets, never in Git; GitHub PAT for ArgoCD lives in git-ignored `terraform/secret.auto.tfvars` |
| Backup creds | `mysqldump --defaults-extra-file` (temp 600 file) — password never in the process list |
| Network | Default-deny NetworkPolicies + per-component allow rules |
| RBAC (K8s) | Dedicated ServiceAccounts per workload, least-privilege Roles, `automountServiceAccountToken: false` |
| RBAC (ArgoCD) | `policy.default: ""` (deny-all) + explicit role grants |
| Pod Security | `pod-security.kubernetes.io/enforce=baseline` on app/infra namespaces |
| Admission control | Gatekeeper DeletionProtection (warn locally, deny for prod) |
| Supply chain | Pinned chart versions; trivy CVE scan; checkov IaC scan; OPA policy gate; SBOM + SLSA provenance on the image build job |
| Scheduling isolation | Workloads tolerate/are pinned to tainted worker nodes; nothing runs on the control-plane |

---

## 6. Performance & resilience features

| Feature | Detail |
|---|---|
| Autoscaling | Backend HPA: 2→6 replicas on CPU 70% / mem 80% |
| Resource governance | requests + limits on every workload (app, MySQL, backup, ArgoCD components, ingress, gatekeeper) |
| Zero-downtime deploys | Rolling update `maxUnavailable: 0`, `maxSurge: 1` (frontend + backend) |
| Disruption protection | PodDisruptionBudgets keep minimum availability during node drains |
| Spread | Multiple replicas (2) for frontend + backend; worker-node scheduling |
| Data durability | StatefulSet volumeClaimTemplate on a `Retain` StorageClass; verified persistence across pod + full-cluster restart |
| Control-plane isolation | Worker taint/toleration keeps app + DB load off the control-plane node |
| ArgoCD tuning | repo-server memory raised to 2Gi (Bitnami chart rendering is memory-heavy) |

---

## 7. Tests & results (verified 2026-05-25)

### Functional / end-to-end (live k3d)
| Test | Result |
|---|---|
| All ArgoCD apps Synced/Healthy | ✅ 7/7 |
| Backend `/health` (DB ping) | ✅ `{"status":"ok","database":"ok"}` |
| Seed data present (`appdb.items`) | ✅ `seed-item-1`, `seed-item-2` |
| CRUD via backend (`/items` POST/GET/DELETE) | ✅ create → 201, delete → 204 |
| Frontend `/api/*` proxy → backend | ✅ `/api/`, `/api/health`, `/api/items` |
| Ingress: frontend `vyking.local:8080`; backend via `/api` proxy | ✅ controller Running, address assigned |
| Backup CronJob every 5 min | ✅ jobs `1/1`, timestamped `appdb_*.sql.gz` on the backup PVC |
| Data persistence across `mysql-0` delete | ✅ same PV rebinds, rows intact |
| Data persistence across full cluster stop/start | ✅ rows intact |
| Gatekeeper enforcement (deny mode) | ✅ `kubectl delete` on a protected Secret → `Forbidden` with custom message; override annotation allows it |

### Static / CI gates
| Gate | Result |
|---|---|
| `terraform fmt -check` / `validate` / `plan` | clean / valid / **No changes** |
| tflint | exit 0 |
| helm lint (`--strict`) | 0 failed |
| kubeconform (`-strict`) | 20/20 valid |
| conftest/OPA — rendered app chart | 540/540 passed, 0 failures |
| conftest/OPA — infra manifests | 0 failures (3 advisory `-local` naming warns) |
| checkov — terraform / helm / kubernetes | 3/3 exit 0 |
| trivy — backend image (Go 1.26) | exit 0, 0 HIGH/CRITICAL (was 1 CRITICAL + 11 HIGH on Go 1.22) |
| go vet / build / test | pass (no test files) |

### CI jobs (`.github/workflows`)
- `ci.yaml`: `lint-terraform`, `lint-helm`, `lint-go` (vet/build/test + trivy), `policy` (conftest), `docker-build` (master only, SBOM + provenance).
- `integration.yaml`: full k3d e2e (push to master / manual).

---

## 8. Known gaps & recommended improvements

Prioritized; **(A) observability is the headline next step you flagged.**

### A. Observability — logs, metrics, dashboards  *(highest value)*
- **Metrics:** add `kube-prometheus-stack` as a new infra ArgoCD app (Prometheus + Grafana + Alertmanager + node/kube-state metrics).
- **MySQL metrics:** `infrastructure/mysql/values.yaml` currently has `metrics.enabled: false` → flip to `true` to expose the Bitnami mysqld-exporter, then add a ServiceMonitor.
- **Free wins:** ArgoCD, Gatekeeper, and ingress-nginx already expose Prometheus metrics — just scrape them. Backend could add a `/metrics` endpoint (e.g. request count/latency, DB pool stats).
- **Logs:** add Loki + a log shipper (Promtail/Alloy) as an infra app; Grafana datasource for both metrics and logs.
- **Dashboards/alerts:** Grafana dashboards for MySQL, app latency, backup success; an alert on "backup CronJob hasn't succeeded in N minutes".
- **Cost / FinOps:** **OpenCost** is deployed (CNCF OSS, reuses our Prometheus) for cost allocation by namespace/workload. On a local cluster these are *estimates* from default on-prem pricing (no cloud bill). **Suggested upgrade: Kubecost** — its richer UI, savings/right-sizing recommendations, and real cloud-billing integration are worth it for a real (especially cloud) cluster; the free tier covers a single cluster.
- **Tracing (stretch):** OpenTelemetry SDK in the backend → an OTel collector → Tempo.

### B. Secrets management
- Replace the bootstrap script with **External Secrets Operator** or **SOPS**/sealed-secrets so secrets are GitOps-managed (encrypted) rather than created out-of-band.

### C. TLS / certs  *(recommended)*
- Local runs ArgoCD with `server.insecure: "true"` (HTTP) and HTTP ingress, with TLS expected to terminate at the edge. **Add `cert-manager` + real TLS** for a prod-like path and drop the insecure flag.
- **Knock-on effect to remove:** because ArgoCD serves HTTP, the CI integration test must log in with `argocd --plaintext` (over a loopback port-forward + the TLS-encrypted kube-apiserver tunnel — no creds cross a network in cleartext, but it's still a workaround). Once ArgoCD serves TLS, the CI can use verified TLS instead of `--plaintext`, and the admin password masking (`::add-mask::`) becomes belt-and-suspenders rather than the primary safeguard.

### D. Backup hardening
- Ship backups to **object storage (S3/MinIO)** instead of a local PVC; add an automated **restore-verification** job and offsite retention.

### E. Availability
- MySQL is single-primary (fine for the brief). For HA: Bitnami MySQL replication or an operator (e.g. Vitess/Percona); ArgoCD HA mode.

### F. Smaller / housekeeping
- `.checkov.yaml` uses `check: [HIGH, CRITICAL]`, a **severity filter that needs a Checkov API key** — currently effectively narrows the scan. Decide: add the key (full severity gating) or drop the filter and manage findings via documented skips.
- Gatekeeper runs **warn** locally so teardown isn't blocked → set **deny** for staging/prod.
- Pin images by **digest** (not just tag) for the app + supporting charts.
- Add **egress** NetworkPolicies (current policies focus on ingress).
- Resolve the 3 conftest naming warnings (infra resources don't follow the `-local` suffix the policy expects) — either rename or relax the policy.
- Backend has **no unit tests** — add a few (handlers + a DB-integration test) so `go test` is meaningful.

---

## 9. How to verify quickly

```bash
# cluster + apps
kubectl get nodes -o wide
kubectl get applications -n argocd

# app end-to-end (port 8085 avoids the k3d LB on 8080)
kubectl port-forward svc/backend-local -n applications 18080:80 &
curl -s localhost:18080/health && curl -s localhost:18080/items

# backups
kubectl get cronjob,jobs -n infrastructure

# static gates (local)
terraform -chdir=terraform validate && terraform -chdir=terraform plan
tflint --chdir=terraform --config="$(pwd)/.tflint.hcl"
helm template vyking applications/ | kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.29.0 -summary
# conftest/checkov/trivy: see README + ci.yaml for the pinned-version invocations
```

> Note: the conftest policies target the **CI-pinned conftest v0.55.0** (run via Docker as CI does). A newer local conftest defaults to Rego v1 and will report parse errors — that's a version mismatch, not a policy defect.

---

## 10. Decision log

Every significant design choice, why it was made, and the trade-off / alternative.

| # | Decision | Rationale | Trade-off / alternative |
|---|---|---|---|
| D1 | **App-of-Apps**: Terraform manages only the 2 parent Applications; child apps are Git-managed | GitOps for the GitOps config itself; keeps Terraform's footprint small | Two control planes (Terraform + ArgoCD) to reason about |
| D2 | ArgoCD CRs applied via **`gavinbunney/kubectl_manifest`**, not `kubernetes_manifest` | Applies `Application`/`AppProject` without the `argoproj.io` CRDs existing at *plan* time — fixes the first-`apply` bootstrap chicken-and-egg | One extra provider dependency |
| D3 | **Multi-source ArgoCD app** for MySQL (upstream Bitnami chart + our values from Git) | Chart upgrades without vendoring; our values stay version-controlled | Slightly more complex Application spec |
| D4 | **Secrets pre-created out-of-band** by `create-secrets.sh` (not in Git/GitOps) | Secrets must never touch Git | Manual bootstrap step; prod path is ESO/SOPS (see §8.B) |
| D5 | **Removed `prevent_destroy`**; rely on layered durability (PV `Retain` + `resource-policy: keep` + ArgoCD `Delete=false`/`prune:false` + Gatekeeper + backups) | `prevent_destroy` can't be conditional and blocked the graded `terraform destroy`/teardown | Durability enforced *below* Terraform rather than by it |
| D6 | **Gatekeeper = `warn` locally, `deny` for prod** | `warn` lets local teardown proceed; `deny` proven to block (see §7) | Local deletes aren't actually blocked (by design) |
| D7 | Gatekeeper: **`enableDeleteOperations` + `oldObject` rego + per-webhook `ServerSideApply=false` + `ignoreDifferences`** | Make deletion-protection actually fire on DELETE *and* keep the app Synced despite controller-managed webhook fields (caBundle/matchConditions) | Non-obvious config; documented inline in `gatekeeper.yaml` |
| D8 | **`bitnamilegacy/mysql` (server) + official `mysql:8.0.36` (backup)** | Bitnami retired `bitnami/*` from Docker Hub (2025); legacy archive keeps the chart pulling; official image gives multi-arch `mysqldump` | Legacy images are unmaintained — swap to a maintained tag/registry in prod |
| D9 | **App images built locally + `k3d image import`; deploy uses `IfNotPresent`, not GHCR** | No registry/auth dependency for a local demo; fast iteration | **The `docker-build`→GHCR job is an artifact path the deploy doesn't consume — see D10** |
| **D10** | **GHCR push kept but not wired into the deploy** *(decision item — your call)* | `ci.yaml` builds+pushes `ghcr.io/eepanagidi/vyking-*` (SBOM + provenance) on master, but `applications/values.yaml` points at locally-imported `vyking-*:0.1.0` | **Option A — keep** as the publish path and, for a remote cluster, point `image.repository` at GHCR + a pushed tag (+ `imagePullSecrets`). **Option B — drop** the push job if local-import is the only intended flow. *Recommend A* (shows a real release path) but make it explicit. |
| D11 | **`docker-build` gated to `push` on `master` only** | Don't publish images for in-flight PRs; mainline-only releases; stops fork PRs pushing to the registry | The job shows as **skipped** on PRs (expected, not a failure) |
| D12 | **Iterate on branch `platform`; PR into protected `master`** | `master` is protected | Extra PR step per change set |
| D13 | **Child apps pinned to `environment=local`; `init.sh` injects repo URL + branch (idempotent)** | Static child manifests reference `-local` AppProjects; `init.sh` makes the repo portable to any fork/branch | A reviewer must run `init.sh` for their own repo |
| D14 | **Backend builds on Go 1.26** | Clears stdlib HIGH/CRITICAL CVEs that failed trivy (`exit-code: 1`) | Must keep current as new stdlib CVEs land |
| D15 | **conftest policies written for CI-pinned conftest v0.55.0 (Rego v0)** | Matches the gate the CI actually runs | Newer local conftest (Rego v1) errors; a v1 rewrite would future-proof |
| D16 | **ArgoCD `server.insecure` + HTTP ingress (local)** | TLS terminated at the edge in local; simpler demo | Not prod-safe — cert-manager + TLS is the prod path (§8.C) |
| D17 | **Distroless `static:nonroot` final image** | Minimal attack surface (no shell/pkg manager); non-root | Harder to debug in-container (no shell) |
| D18 | **Worker taints + tolerations; nothing scheduled on the control-plane** | Realistic node isolation; protects the control-plane | Workloads must carry the toleration + nodeSelector |
| D19 | **ArgoCD repo-server memory = 2Gi** | Bitnami MySQL chart rendering OOMed at 512Mi/1Gi | Higher baseline memory for the demo |
| D20 | **`IMPLEMENTATION_REVIEW.md` kept out of Git by default** | It's a reviewer aid, not a submission artifact | Move/commit it if you want it in the repo |

> **Open decision needing your input: D10** (keep vs. drop the GHCR push path). Everything else is settled.

