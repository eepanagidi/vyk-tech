package kubernetes

import future.keywords.in

labeled_workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "CronJob", "Job"}

required_labels := {
  "app.kubernetes.io/name",
  "app.kubernetes.io/component",
  "app.kubernetes.io/managed-by",
}

deny[msg] {
  input.kind in labeled_workload_kinds
  labels := object.get(input, ["metadata", "labels"], {})
  missing := required_labels - {k | labels[k]}
  count(missing) > 0
  msg := sprintf("%s/%s is missing required labels: %v", [input.kind, input.metadata.name, missing])
}

deny[msg] {
  input.kind in labeled_workload_kinds
  # CronJob nests its pod template under spec.jobTemplate.spec.template; every
  # other workload kind uses spec.template. Fall back to the CronJob path so the
  # check works for both (the default arg is the CronJob lookup).
  pod_labels := object.get(
    input,
    ["spec", "template", "metadata", "labels"],
    object.get(input, ["spec", "jobTemplate", "spec", "template", "metadata", "labels"], {}),
  )
  missing := {"app.kubernetes.io/name", "app.kubernetes.io/component"} - {k | pod_labels[k]}
  count(missing) > 0
  msg := sprintf("%s/%s pod template is missing required labels: %v", [input.kind, input.metadata.name, missing])
}
