variable "name" {
  description = "AppProject name (e.g. infrastructure-local)"
  type        = string
}

variable "namespace" {
  description = "Namespace ArgoCD runs in (where AppProjects live)"
  type        = string
}

variable "description" {
  description = "Human-readable AppProject description"
  type        = string
}

variable "labels" {
  description = "Common labels applied to the AppProject"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Optional metadata annotations; omitted entirely when empty"
  type        = map(string)
  default     = {}
}

variable "source_repos" {
  description = "Allowed source repositories"
  type        = list(string)
}

variable "destinations" {
  description = "Allowed deploy destinations (cluster + namespace)"
  type = list(object({
    server    = string
    namespace = string
  }))
}

variable "cluster_resource_whitelist" {
  description = "Cluster-scoped resource kinds the project may manage"
  type = list(object({
    group = string
    kind  = string
  }))
  default = []
}

variable "namespace_resource_whitelist" {
  description = "Namespaced resource kinds the project may manage"
  type = list(object({
    group = string
    kind  = string
  }))
  default = []
}

variable "orphaned_resources_warn" {
  description = "Warn (not delete) on orphaned resources — typically production only"
  type        = bool
  default     = false
}
