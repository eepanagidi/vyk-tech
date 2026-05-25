output "namespace" {
  description = "The namespace ArgoCD was installed into"
  value       = kubernetes_namespace.this.metadata[0].name
}

output "release_name" {
  description = "The ArgoCD Helm release name"
  value       = helm_release.this.name
}
