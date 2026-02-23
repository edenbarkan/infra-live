# --- INGRESS STACK ---
# This module deploys the full ingress pipeline:
#
#   Internet → ALB (ingressClassName: alb) → NGINX Controller (ingressClassName: nginx) → App Pods
#
# Two controllers process two different Ingress resources:
#   1. AWS Load Balancer Controller  → watches "alb" class   → creates the ALB
#   2. NGINX Ingress Controller      → watches "nginx" class  → routes to app services
#
# The ALB Ingress resource below creates the internet-facing load balancer.
# App-level Ingress resources (in helm-charts repo) define per-app routing rules.

resource "helm_release" "ingress_nginx" {
  namespace        = "ingress-nginx"
  create_namespace = true
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.14.3"

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
        default = false # Apps must explicitly specify ingressClassName: nginx
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
          enabled = false # Set true if you have Prometheus
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

      # Replicas: configurable via env.hcl (dev: 1, prod: 2)
      replicaCount = var.replica_count
    }
  })]
}

# --- ALB INGRESS: Creates an internet-facing ALB that routes traffic to NGINX ---
# AWS Load Balancer Controller watches for Ingress with ingressClassName: alb
# and automatically provisions an ALB + Target Group
# Traffic flow: Internet → ALB → NGINX (NodePort) → App Pods

resource "kubernetes_ingress_v1" "alb_to_nginx" {
  metadata {
    name      = "alb-to-nginx"
    namespace = "ingress-nginx"
    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "instance"
      "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }])
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
      "alb.ingress.kubernetes.io/tags"             = "Environment=${var.environment},ManagedBy=terragrunt"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "ingress-nginx-controller"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}
