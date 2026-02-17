output "namespace" {
  description = "Namespace where ingress-nginx is deployed"
  value       = "ingress-nginx"
}

output "service_name" {
  description = "Service name of ingress-nginx controller"
  value       = "ingress-nginx-controller"
}

output "alb_dns_name" {
  description = "DNS name of the ALB fronting NGINX (populated after apply)"
  value       = try(kubernetes_ingress_v1.alb_to_nginx.status[0].load_balancer[0].ingress[0].hostname, "pending")
}
