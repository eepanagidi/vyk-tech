package terraform

import future.keywords.in

required_tags := {"environment", "project", "managed_by", "owner"}

deny[msg] {
  resource := input.resource.helm_release[name]
  provided := {tag | resource.values.set[tag]}
  missing := required_tags - provided
  count(missing) > 0
  msg := sprintf("helm_release.%s is missing required tags: %v", [name, missing])
}

deny[msg] {
  resource := input.resource.kubernetes_namespace[name]
  labels := object.get(resource, ["values", "metadata", "labels"], {})
  missing := required_tags - {k | labels[k]}
  count(missing) > 0
  msg := sprintf("kubernetes_namespace.%s is missing required labels: %v", [name, missing])
}
