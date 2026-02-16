output "namespace" {
  description = "Namespace where ingress-nginx is deployed"
  value       = "ingress-nginx"
}

output "service_name" {
  description = "Service name of ingress-nginx controller"
  value       = "ingress-nginx-controller"
}
