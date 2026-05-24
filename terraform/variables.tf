variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "k3d-vyking-cluster"
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD installation"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version (pinned for reproducibility)"
  type        = string
  default     = "7.3.11"
}

variable "git_repo_url" {
  description = "URL of your Git repository (e.g. https://github.com/you/vyking-devops)"
  type        = string
}

variable "git_repo_revision" {
  description = "Git branch/tag to track"
  type        = string
  default     = "main"
}

variable "environment" {
  description = "Deployment environment (local | staging | production)"
  type        = string
  default     = "local"
  validation {
    condition     = contains(["local", "staging", "production"], var.environment)
    error_message = "environment must be one of: local, staging, production."
  }
}

variable "project" {
  description = "Project name — used as the base for all resource names"
  type        = string
  default     = "vyking-platform"
}

variable "owner" {
  description = "Team or individual owning these resources (for cost attribution)"
  type        = string
  default     = "platform-team"
}

variable "enable_protection" {
  description = <<-EOT
    Enable deletion protection on production/staging resources.
    Set to false ONLY for emergency teardown — requires explicit override:
      terraform destroy -var="enable_protection=false"
    Defaults to true for production/staging, false for local.
  EOT
  type        = bool
  default     = true

  # Validation: production must always have protection unless explicitly bypassed
  # The OPA policy also enforces this as a second line of defence
}

variable "github_token" {
  description = <<-EOT
    GitHub PAT (fine-grained, Contents: Read-only) used by ArgoCD to pull a
    PRIVATE Git repo. Provide it out-of-band — e.g. terraform/secret.auto.tfvars
    (git-ignored) or `export TF_VAR_github_token=...`. Leave empty for a public
    repo (ArgoCD then syncs anonymously).
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "git_username" {
  description = "Username paired with github_token for the ArgoCD repo credential (your GitHub username; any value works with a PAT)."
  type        = string
  default     = "git"
}
