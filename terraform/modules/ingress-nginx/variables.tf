variable "namespace_labels" {
  description = "Labels for the ingress-nginx namespace"
  type        = map(string)
  default     = {}
}

variable "helm_common_labels" {
  description = "Values for the chart's commonLabels (environment, project, managed_by)"
  type        = map(string)
  default     = {}
}
