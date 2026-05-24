package terraform

deny[msg] {
  resource := input.resource.helm_release[name]
  not resource.values.version
  msg := sprintf("helm_release.%s must pin a chart version", [name])
}

deny[msg] {
  resource := input.resource.helm_release[name]
  resource.values.atomic == false
  msg := sprintf("helm_release.%s: atomic must not be false — failed deploys should roll back", [name])
}
