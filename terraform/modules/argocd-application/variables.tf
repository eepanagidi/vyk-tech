variable "name" {
  description = "Application name (e.g. infrastructure-local)"
  type        = string
}

variable "namespace" {
  description = "Namespace ArgoCD runs in (where the Application object lives)"
  type        = string
}

variable "project" {
  description = "AppProject this Application belongs to"
  type        = string
}

variable "labels" {
  description = "Labels applied to the Application"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Annotations applied to the Application"
  type        = map(string)
  default     = {}
}

variable "repo_url" {
  description = "Git repository the Application syncs from"
  type        = string
}

variable "target_revision" {
  description = "Git branch/tag/commit to track"
  type        = string
}

variable "source_path" {
  description = "Path within the repo to sync"
  type        = string
}

variable "source_helm" {
  description = "Optional Helm source block ({valueFiles, parameters}); omitted when null"
  type        = any
  default     = null
}

variable "dest_server" {
  description = "Target cluster API server"
  type        = string
  default     = "https://kubernetes.default.svc"
}

variable "dest_namespace" {
  description = "Namespace the Application deploys into"
  type        = string
}

variable "sync_options" {
  description = "ArgoCD syncPolicy.syncOptions"
  type        = list(string)
}

variable "automated" {
  description = "ArgoCD automated sync block ({prune, selfHeal}); omitted when null (manual sync)"
  type        = any
  default     = null
}
