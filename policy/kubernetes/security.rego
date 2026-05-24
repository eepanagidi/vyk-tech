package kubernetes

import future.keywords.in

container_kinds := {"Deployment", "StatefulSet", "DaemonSet"}

deny[msg] {
  input.kind in container_kinds
  container := input.spec.template.spec.containers[_]
  not container.resources.limits
  msg := sprintf("%s/%s: container '%s' must define resource limits", [input.kind, input.metadata.name, container.name])
}

deny[msg] {
  input.kind in container_kinds
  container := input.spec.template.spec.containers[_]
  not container.resources.requests
  msg := sprintf("%s/%s: container '%s' must define resource requests", [input.kind, input.metadata.name, container.name])
}

deny[msg] {
  input.kind in container_kinds
  container := input.spec.template.spec.containers[_]
  sc := object.get(container, "securityContext", {})
  not sc.runAsNonRoot == true
  msg := sprintf("%s/%s: container '%s' must set runAsNonRoot=true", [input.kind, input.metadata.name, container.name])
}

deny[msg] {
  input.kind in container_kinds
  container := input.spec.template.spec.containers[_]
  sc := object.get(container, "securityContext", {})
  not sc.allowPrivilegeEscalation == false
  msg := sprintf("%s/%s: container '%s' must set allowPrivilegeEscalation=false", [input.kind, input.metadata.name, container.name])
}

deny[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.livenessProbe
  msg := sprintf("Deployment/%s: container '%s' must define a livenessProbe", [input.metadata.name, container.name])
}

deny[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.readinessProbe
  msg := sprintf("Deployment/%s: container '%s' must define a readinessProbe", [input.metadata.name, container.name])
}

deny[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  endswith(container.image, ":latest")
  msg := sprintf("Deployment/%s: container '%s' must not use ':latest' tag", [input.metadata.name, container.name])
}
