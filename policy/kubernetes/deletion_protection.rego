# ──────────────────────────────────────────────
# OPA Policy: Deletion protection enforcement
#
# Rules:
#   1. Protected resources (production/staging) must carry
#      the vyking.io/deletion-protected="true" annotation
#
#   2. kubectl delete on a protected resource is denied
#      (requires Gatekeeper ConstraintTemplate to enforce at admission)
#
#   3. Resource names must include their environment suffix
#      so you always know what you're looking at
# ──────────────────────────────────────────────
package kubernetes

import future.keywords.in

protected_environments := {"production", "staging"}

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "Service",
                   "PersistentVolumeClaim", "ConfigMap", "ServiceAccount"}

# ── Rule 1: Protected resources must carry the annotation ─────────────────
deny[msg] {
  input.kind in workload_kinds
  env := object.get(input, ["metadata", "labels", "environment"], "")
  env in protected_environments
  annotations := object.get(input, ["metadata", "annotations"], {})
  annotations["vyking.io/deletion-protected"] != "true"
  msg := sprintf(
    "%s/%s is in environment '%s' but is missing annotation vyking.io/deletion-protected=true",
    [input.kind, input.metadata.name, env]
  )
}

# ── Rule 2: Deletion of protected resources is denied ─────────────────────
# This rule is evaluated by Gatekeeper at admission time.
# input.request.operation == "DELETE" is set by the K8s API server.
deny[msg] {
  input.request.operation == "DELETE"
  annotations := object.get(input.object, ["metadata", "annotations"], {})
  annotations["vyking.io/deletion-protected"] == "true"
  # Allow if deletion-override annotation is explicitly set
  not annotations["vyking.io/deletion-override"] == "true"
  msg := sprintf(
    "Deletion of %s/%s is protected. To override: kubectl annotate %s %s vyking.io/deletion-override=true",
    [input.object.kind, input.object.metadata.name,
     input.object.kind, input.object.metadata.name]
  )
}

# ── Rule 3: Resource names must include environment suffix ─────────────────
warn[msg] {
  input.kind in workload_kinds
  env := object.get(input, ["metadata", "labels", "environment"], "")
  env != ""
  name := input.metadata.name
  not endswith(name, concat("", ["-", env]))
  # Exception: ConfigMaps and Secrets with fixed names (e.g. "mysql-credentials")
  not input.kind in {"ConfigMap", "Secret"}
  msg := sprintf(
    "%s/%s: name should end with '-%s' to indicate its environment",
    [input.kind, name, env]
  )
}

# ── Rule 4: PVCs with stateful data must use a Retain storage class ──────────
# "Delete" reclaim policy silently destroys data when PVC is removed.
warn[msg] {
  input.kind == "PersistentVolumeClaim"
  input.metadata.annotations["vyking.io/contains-stateful-data"] == "true"
  sc := object.get(input.spec, "storageClassName", "")
  not endswith(sc, "-retain")
  msg := sprintf(
    "PVC/%s contains stateful data but storageClassName '%s' may not use reclaimPolicy=Retain. Use a '-retain' suffixed StorageClass.",
    [input.metadata.name, sc]
  )
}

# ── Rule 5: StatefulSets must not have automated PVC deletion enabled ─────────
deny[msg] {
  input.kind == "StatefulSet"
  input.metadata.annotations["vyking.io/deletion-protected"] == "true"
  # persistentVolumeClaimRetentionPolicy.whenDeleted=Delete wipes PVCs on StatefulSet deletion
  policy := object.get(input.spec, "persistentVolumeClaimRetentionPolicy", {})
  policy.whenDeleted == "Delete"
  msg := sprintf(
    "StatefulSet/%s is deletion-protected but persistentVolumeClaimRetentionPolicy.whenDeleted=Delete — this would destroy PVCs if the StatefulSet is deleted. Set to 'Retain'.",
    [input.metadata.name]
  )
}
