# ──────────────────────────────────────────────
# TFLint configuration
# ──────────────────────────────────────────────

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Enforce variable descriptions
rule "terraform_documented_variables" {
  enabled = true
}

# Enforce output descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

# Require pinned module versions
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "semver"
}

# No legacy lifecycle ignore_changes = all
rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}
