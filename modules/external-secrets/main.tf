# --- IAM POLICY: Limit access to environment-specific secrets ---
# Each cluster can only read secrets matching its namespace prefixes
# Dev cluster: dev/*, staging/*    Prod cluster: production/*

resource "aws_iam_policy" "eso" {
  name        = "${var.cluster_name}-eso"
  description = "Allow External Secrets to read from Secrets Manager (${join(", ", var.secret_prefixes)} prefixes)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [for prefix in var.secret_prefixes : "arn:aws:secretsmanager:${var.region}:*:secret:${prefix}/*"]
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

# --- POD IDENTITY: IAM Role for ESO ---
# Pod Identity replaces IRSA — no OIDC provider needed, credentials injected directly

resource "aws_iam_role" "eso" {
  name = "${var.cluster_name}-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso.arn
}

# --- EXTERNAL SECRETS OPERATOR HELM CHART ---

resource "helm_release" "external_secrets" {
  namespace        = "external-secrets"
  create_namespace = true
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.12.1"

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

  depends_on = [aws_eks_pod_identity_association.eso]
}

# --- CLUSTERSECRETSTORE: Default store pointing to AWS Secrets Manager ---
# With Pod Identity, no auth config needed — credentials are injected directly
# into the ESO pod via AWS_CONTAINER_CREDENTIALS_FULL_URI

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
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets, aws_eks_pod_identity_association.eso]
}
