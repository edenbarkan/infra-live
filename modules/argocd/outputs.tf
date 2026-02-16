output "namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = "argocd"
}

output "server_url" {
  description = "ArgoCD server URL"
  value       = "https://${var.domain}"
}
