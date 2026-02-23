resource "helm_release" "argocd" {
  namespace        = "argocd"
  create_namespace = true
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.8.0"

  values = [yamlencode({
    global = {
      domain = var.domain
    }

    configs = {
      params = {
        # TLS termination happens at ALB, not ArgoCD
        "server.insecure" = true
      }
    }

    server = {
      # ArgoCD UI accessible via ingress-nginx
      ingress = {
        enabled          = true
        ingressClassName = "nginx"
        hosts            = [var.domain]
        annotations = {
          # Optional: add authentication, rate limiting, etc.
        }
      }

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
    }

    # ApplicationSet controller: generates multiple apps from templates
    applicationSet = {
      enabled = true
    }

    # Repo server: clones Git repos
    repoServer = {
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    }

    # Controller: syncs apps to desired state
    controller = {
      resources = {
        requests = {
          cpu    = "250m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }

      # Run on system nodes
      tolerations = [{
        key      = "CriticalAddonsOnly"
        operator = "Exists"
        effect   = "NoSchedule"
      }]
    }
  })]
}

# --- ARGOCD PROJECT: Environment-scoped permissions ---
# Limits which repos and namespaces ArgoCD can deploy to

resource "kubectl_manifest" "argocd_project" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = var.environment
      namespace = "argocd"
    }
    spec = {
      description = "${var.environment} environment"

      # Which Git repos are allowed
      sourceRepos = [var.helm_charts_repo_url]

      # Which namespaces can be deployed to
      destinations = [
        for ns in var.namespaces : {
          namespace = ns
          server    = "https://kubernetes.default.svc"
        }
      ]

      # Allow Namespace creation (needed for CreateNamespace=true sync option)
      clusterResourceWhitelist = [{ group = "", kind = "Namespace" }]

      # All namespace-scoped resources allowed
      namespaceResourceWhitelist = [{ group = "*", kind = "*" }]
    }
  })

  depends_on = [helm_release.argocd]
}

# --- APPLICATIONSET: Auto-generates Applications for each namespace ---
# Creates one Application per namespace (e.g., myapp-dev, myapp-staging)

resource "kubectl_manifest" "applicationset" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "myapp-${var.environment}-envs"
      namespace = "argocd"
    }
    spec = {
      generators = [{
        list = {
          elements = [
            for ns in var.namespaces : {
              env       = ns
              namespace = ns
            }
          ]
        }
      }]

      template = {
        metadata = {
          name = "myapp-{{env}}"
        }
        spec = {
          project = var.environment

          source = {
            repoURL        = var.helm_charts_repo_url
            targetRevision = "main"
            path           = "charts/generic-app"
            helm = {
              valueFiles = [
                "../../apps/myapp/base/values.yaml",
                "../../apps/myapp/overlays/{{env}}/values.yaml"
              ]
            }
          }

          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "{{namespace}}"
          }

          # Dev/staging: auto-sync (immediate deployment)
          # Production: manual sync only (requires approval in ArgoCD UI)
          syncPolicy = merge(
            {
              syncOptions = ["CreateNamespace=true"]
            },
            var.auto_sync ? {
              automated = {
                prune    = true
                selfHeal = true
              }
            } : {}
          )
        }
      }
    }
  })

  depends_on = [
    helm_release.argocd,
    kubectl_manifest.argocd_project
  ]
}
