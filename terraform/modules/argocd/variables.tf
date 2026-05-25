variable "release_name" {
  description = "Helm release name for ArgoCD (e.g. vyking-platform-local-argocd)"
  type        = string
}

variable "namespace" {
  description = "Namespace to install ArgoCD into"
  type        = string
}

variable "chart_version" {
  description = "argo-cd Helm chart version"
  type        = string
}

variable "namespace_labels" {
  description = "Labels for the ArgoCD namespace"
  type        = map(string)
  default     = {}
}

variable "namespace_annotations" {
  description = "Annotations for the ArgoCD namespace"
  type        = map(string)
  default     = {}
}

variable "helm_common_labels" {
  description = "Values injected as global.commonLabels.<key> on the ArgoCD release"
  type        = map(string)
  default     = {}
}

variable "git_repo_url" {
  description = "Git repo URL for the ArgoCD repository credential"
  type        = string
}

variable "git_username" {
  description = "Username for the repository credential"
  type        = string
  default     = "git"
}

variable "github_token" {
  description = "PAT for a PRIVATE repo; when empty no repository credential is created"
  type        = string
  default     = ""
  sensitive   = true
}
