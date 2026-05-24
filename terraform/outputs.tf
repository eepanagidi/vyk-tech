output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_admin_password_cmd" {
  description = "Retrieve the initial ArgoCD admin password"
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
}

output "argocd_port_forward_cmd" {
  description = "Port-forward to access the ArgoCD UI"
  value       = "kubectl port-forward svc/argocd-server -n ${var.argocd_namespace} 8080:80"
}

output "git_repo_url" {
  description = "Git repository being tracked by ArgoCD"
  value       = var.git_repo_url
}

output "ingress_hosts_setup" {
  description = "Add these entries to /etc/hosts for local ingress access"
  value       = "echo '127.0.0.1 vyking.local api.vyking.local' | sudo tee -a /etc/hosts"
}

output "frontend_url" {
  description = "Frontend URL (after /etc/hosts setup)"
  value       = "http://vyking.local:8080"
}

output "backend_api_url" {
  description = "Backend API URL (after /etc/hosts setup)"
  value       = "http://api.vyking.local:8080"
}

output "resource_names" {
  description = "All resource names generated for this environment — use these in kubectl commands"
  value = {
    environment      = var.environment
    argocd           = local.names.argocd
    ingress          = local.names.ingress
    argocd_app_infra = "infrastructure-${var.environment}"
    argocd_app_apps  = "applications-${var.environment}"
    backend          = "backend-${var.environment}"
    frontend         = "frontend-${var.environment}"
    configmap_app    = "app-config-${var.environment}"
    configmap_nginx  = "nginx-config-${var.environment}"
  }
}

output "protection_status" {
  description = "Deletion protection status for this environment"
  value = {
    environment        = var.environment
    is_protected       = local.is_protected
    is_production      = local.is_production
    protection_enabled = local.enable_protection
    argocd_sync_mode   = local.is_production ? "MANUAL — all syncs require UI approval" : "AUTOMATED"
  }
}

output "deploy_commands" {
  description = "Commands for common operations in this environment"
  value = {
    apply       = "terraform apply -var-file=environments/${var.environment}.tfvars"
    destroy     = var.environment == "production" ? "See scripts/emergency-destroy.sh" : "terraform destroy -var-file=environments/${var.environment}.tfvars"
    argocd_sync = local.is_production ? "argocd app sync infrastructure-production  # Manual approval required" : "ArgoCD syncs automatically"
  }
}
