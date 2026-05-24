# ──────────────────────────────────────────────
# OPA Policy: Database resource protection
#
# Enforces that stateful database resources:
#   1. Always have the Retain storage class (not Delete)
#   2. Carry deletion-protected and stateful-data annotations
#   3. Cannot be deleted via the API without an override
#   4. StatefulSets serving DB workloads must have PVCs with Retain
# ──────────────────────────────────────────────
package kubernetes

import future.keywords.in

db_labels := {
  "app.kubernetes.io/component": "database",
}

# ── Rule 1: PVCs for DB workloads must use the Retain StorageClass ────────
deny[msg] {
  input.kind == "PersistentVolumeClaim"
  # Check if this PVC belongs to a DB workload by label
  labels := object.get(input, ["metadata", "labels"], {})
  labels["app.kubernetes.io/component"] == "database"
  # StorageClass must be mysql-retain (or any class ending in -retain)
  sc := object.get(input, ["spec", "storageClassName"], "")
  not endswith(sc, "-retain")
  msg := sprintf(
    "PVC/%s is a database volume but uses storageClass '%s' — must use a Retain storageClass to prevent data loss on deletion",
    [input.metadata.name, sc]
  )
}

# ── Rule 2: DB PVCs must carry the deletion-protected annotation ──────────
deny[msg] {
  input.kind == "PersistentVolumeClaim"
  labels := object.get(input, ["metadata", "labels"], {})
  labels["app.kubernetes.io/component"] == "database"
  annotations := object.get(input, ["metadata", "annotations"], {})
  annotations["vyking.io/deletion-protected"] != "true"
  msg := sprintf(
    "PVC/%s is a database volume but is missing annotation vyking.io/deletion-protected=true",
    [input.metadata.name]
  )
}

# ── Rule 3: DB PVCs must carry the ArgoCD Delete=false sync option ────────
deny[msg] {
  input.kind == "PersistentVolumeClaim"
  labels := object.get(input, ["metadata", "labels"], {})
  labels["app.kubernetes.io/component"] == "database"
  annotations := object.get(input, ["metadata", "annotations"], {})
  not contains(object.get(annotations, "argocd.argoproj.io/sync-options", ""), "Delete=false")
  msg := sprintf(
    "PVC/%s is missing argocd.argoproj.io/sync-options: Delete=false — ArgoCD could delete this volume",
    [input.metadata.name]
  )
}

# ── Rule 4: DB PVCs must carry the Helm keep policy ──────────────────────
deny[msg] {
  input.kind == "PersistentVolumeClaim"
  labels := object.get(input, ["metadata", "labels"], {})
  labels["app.kubernetes.io/component"] == "database"
  annotations := object.get(input, ["metadata", "annotations"], {})
  annotations["helm.sh/resource-policy"] != "keep"
  msg := sprintf(
    "PVC/%s is missing annotation helm.sh/resource-policy=keep — helm uninstall would delete this volume",
    [input.metadata.name]
  )
}

# ── Rule 5: Deletion of DB resources is blocked ───────────────────────────
deny[msg] {
  input.request.operation == "DELETE"
  input.kind in {"PersistentVolumeClaim", "StatefulSet", "Secret"}
  annotations := object.get(input.object, ["metadata", "annotations"], {})
  annotations["vyking.io/contains-stateful-data"] == "true"
  not annotations["vyking.io/deletion-override"] == "true"
  msg := sprintf(
    "Deletion of %s/%s is blocked — this resource contains stateful data. Annotate with vyking.io/deletion-override=true to proceed.",
    [input.kind, input.object.metadata.name]
  )
}

# ── Rule 6: MySQL credentials Secret must be protected ───────────────────
warn[msg] {
  input.kind == "Secret"
  input.metadata.name == "mysql-credentials"
  annotations := object.get(input, ["metadata", "annotations"], {})
  annotations["vyking.io/deletion-protected"] != "true"
  msg := "Secret/mysql-credentials is missing vyking.io/deletion-protected=true — loss of this secret requires manual DB password reset"
}

# ── Rule 7: StorageClass used by DB PVCs must have Retain reclaimPolicy ───
deny[msg] {
  input.kind == "StorageClass"
  labels := object.get(input, ["metadata", "labels"], {})
  labels["app.kubernetes.io/component"] == "database"
  input.reclaimPolicy != "Retain"
  msg := sprintf(
    "StorageClass/%s is used for database storage but reclaimPolicy=%s — must be Retain",
    [input.metadata.name, input.reclaimPolicy]
  )
}
