package kubernetes

import future.keywords.in

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "CronJob", "Job"}

required_labels := {
  "app.kubernetes.io/name",
  "app.kubernetes.io/component",
  "app.kubernetes.io/managed-by",
}

deny[msg] {
  input.kind in workload_kinds
  labels := object.get(input, ["metadata", "labels"], {})
  missing := required_labels - {k | labels[k]}
  count(missing) > 0
  msg := sprintf("%s/%s is missing required labels: %v", [input.kind, input.metadata.name, missing])
}

deny[msg] {
  input.kind in workload_kinds
  pod_labels := object.get(input, ["spec", "template", "metadata", "labels"], {})
  missing := {"app.kubernetes.io/name", "app.kubernetes.io/component"} - {k | pod_labels[k]}
  count(missing) > 0
  msg := sprintf("%s/%s pod template is missing required labels: %v", [input.kind, input.metadata.name, missing])
}
