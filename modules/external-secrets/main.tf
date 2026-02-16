# --- IAM POLICY: Limit access to environment-specific secrets ---
# Dev can only read secrets under "dev/*" prefix
# Prod can only read secrets under "prod/*" prefix

resource "aws_iam_policy" "eso" {
  name        = "${var.cluster_name}-eso"
  description = "Allow External Secrets to read from Secrets Manager (${var.environment} only)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Only allow reading secrets with this environment's prefix
        Resource = "arn:aws:secretsmanager:${var.region}:*:secret:${var.environment}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# --- IRSA: IAM Role for Service Account ---

module "eso_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-external-secrets"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    policy = aws_iam_policy.eso.arn
  }

  tags = var.tags
}

# --- EXTERNAL SECRETS OPERATOR HELM CHART ---

resource "helm_release" "external_secrets" {
  namespace        = "external-secrets"
  create_namespace = true
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.9.13"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eso_irsa.iam_role_arn
  }

  # Run on system nodes
  set {
    name  = "tolerations[0].key"
    value = "CriticalAddonsOnly"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }
}

# --- CLUSTERSECRETSTORE: Default store pointing to AWS Secrets Manager ---

resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "aws-secrets-manager" }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}
