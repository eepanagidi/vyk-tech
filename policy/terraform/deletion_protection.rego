# ──────────────────────────────────────────────
# OPA Policy: Terraform deletion protection
#
# Enforces that production/staging Helm releases
# and namespaces cannot be destroyed without
# explicitly setting enable_protection=false.
# ──────────────────────────────────────────────
package terraform

# Required for the `some x in ...` / `x in set` expressions below. Without it,
# conftest/OPA fails to PARSE this file — and since conftest loads every file in
# policy/ before evaluating, that parse error breaks the whole policy run (even
# though CI only evaluates the `kubernetes` package).
import future.keywords.in

protected_envs := {"production", "staging"}

# Helm releases in protected environments must have lifecycle.prevent_destroy
deny[msg] {
  resource := input.resource.helm_release[name]
  env := object.get(resource, ["values", "set"], {})
  # Check if environment label is production/staging
  some set_item in object.get(resource, ["values", "set"], [])
  set_item.name == "global.commonLabels.environment"
  set_item.value in protected_envs
  # prevent_destroy must be in lifecycle block
  not object.get(resource, ["lifecycle", "prevent_destroy"], false)
  msg := sprintf(
    "helm_release.%s is in a protected environment but missing lifecycle.prevent_destroy=true",
    [name]
  )
}

# Namespaces in protected environments must have prevent_destroy
deny[msg] {
  resource := input.resource.kubernetes_namespace[name]
  labels := object.get(resource, ["values", "metadata", "labels"], {})
  labels["environment"] in protected_envs
  not object.get(resource, ["lifecycle", "prevent_destroy"], false)
  msg := sprintf(
    "kubernetes_namespace.%s is in a protected environment but missing lifecycle.prevent_destroy=true",
    [name]
  )
}
