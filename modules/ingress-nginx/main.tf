resource "helm_release" "ingress_nginx" {
  namespace        = "ingress-nginx"
  create_namespace = true
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.10.0"

  values = [yamlencode({
    controller = {
      # NodePort: ALB sends traffic here
      service = {
        type = "NodePort"
      }

      # Ingress class configuration
      ingressClassResource = {
        name    = "nginx"
        enabled = true
        default = false  # Apps must explicitly specify ingressClassName: nginx
      }

      # Trust X-Forwarded headers from ALB
      config = {
        use-forwarded-headers      = "true"
        compute-full-forwarded-for = "true"
        use-proxy-protocol         = "false"
      }

      # Metrics for monitoring
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = false  # Set true if you have Prometheus
        }
      }

      # Run on system nodes
      tolerations = [{
        key      = "CriticalAddonsOnly"
        operator = "Exists"
        effect   = "NoSchedule"
      }]

      # Resource limits
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }

      # Replicas: 2 for dev (cost), 3 for prod (HA)
      replicaCount = var.environment == "prod" ? 3 : 2
    }
  })]
}
