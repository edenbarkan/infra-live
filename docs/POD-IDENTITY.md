# EKS Pod Identity Migration Guide

Guide for using EKS Pod Identity (the modern AWS-recommended authentication method).

## Overview

**EKS Pod Identity** is the modern, AWS-managed authentication method for Kubernetes pods to assume IAM roles. It replaces the older IRSA (IAM Roles for Service Accounts) approach.

### Why Pod Identity?

| Feature | IRSA (Old) | Pod Identity (New) |
|---------|-----------|-------------------|
| **Setup Complexity** | Complex (OIDC provider, annotations) | Simple (one resource) |
| **Management** | Manual OIDC thumbprint rotation | Fully AWS-managed |
| **Performance** | Slower (OIDC validation) | Faster (direct AWS API) |
| **Debugging** | Hard (OIDC errors unclear) | Easy (clear AWS API errors) |
| **AWS Recommendation** | Legacy (deprecated) | ✅ Recommended |

## Architecture

### IRSA (Old Approach)

```
┌─────────┐     ┌──────────┐     ┌───────────┐
│   Pod   │────▶│  OIDC    │────▶│    IAM    │
│         │     │ Provider │     │   Role    │
└─────────┘     └──────────┘     └───────────┘
                     ↓
            Annotation on SA
            Complex trust policy
```

### Pod Identity (New Approach)

```
┌─────────┐     ┌─────────────────┐     ┌───────────┐
│   Pod   │────▶│ Pod Identity    │────▶│    IAM    │
│         │     │  Association    │     │   Role    │
└─────────┘     └─────────────────┘     └───────────┘
                Direct AWS-managed connection
                No annotations needed!
```

## Implementation

### Prerequisites

**EKS Pod Identity Agent** must be installed as a cluster addon:

```hcl
# modules/eks/main.tf
cluster_addons = {
  eks-pod-identity-agent = {
    most_recent = true
  }
}
```

This creates a DaemonSet that runs on every node.

### Verify Agent is Running

```bash
kubectl get daemonset -n kube-system eks-pod-identity-agent
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

## Karpenter with Pod Identity

### Terraform Configuration

```hcl
# modules/karpenter/main.tf
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = var.cluster_name

  # Enable Pod Identity
  enable_pod_identity             = true
  create_pod_identity_association = true

  # CRITICAL: Must match Helm namespace
  namespace = "karpenter"

  enable_spot_termination = true
}

# Helm release configuration
resource "helm_release" "karpenter" {
  namespace = "karpenter"  # Must match above!

  values = [yamlencode({
    serviceAccount = {
      name = "karpenter"  # Must match Pod Identity Association
    }
    # NO role-arn annotation needed!
  })]
}
```

### Key Points

1. **Namespace must match**: Pod Identity Association namespace must match Helm release namespace
2. **No annotations**: Don't add `eks.amazonaws.com/role-arn` annotation
3. **Service account name**: Must match the association (usually same as chart name)

### Verify Configuration

```bash
# Check Pod Identity Association
aws eks list-pod-identity-associations \
  --cluster-name myapp-dev --region us-east-1

# Should show:
# - Namespace: karpenter
# - Service account: karpenter
# - IAM role: KarpenterController-xxx

# Check pods can assume role
kubectl logs -n karpenter deployment/karpenter | grep -i assume
```

## AWS Load Balancer Controller with Pod Identity

```hcl
# modules/aws-load-balancer-controller/main.tf
resource "aws_iam_role" "lbc" {
  name = "${var.cluster_name}-aws-lbc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
}
```

## External Secrets with Pod Identity

```hcl
# modules/external-secrets/main.tf
resource "aws_iam_role" "external_secrets" {
  assume_role_policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn
}
```

## Troubleshooting

### Common Issues

#### 1. Pod Identity Agent Not Installed

**Symptom**: Pods can't assume IAM role

**Fix**:
```bash
# Check if addon exists
aws eks describe-addon --cluster-name myapp-dev \
  --addon-name eks-pod-identity-agent

# If not, add to cluster addons in modules/eks/main.tf
```

#### 2. Namespace Mismatch

**Symptom**: `AccessDenied` or `not authorized to perform sts:AssumeRole`

**Fix**:
```bash
# Check association namespace
aws eks describe-pod-identity-association \
  --cluster-name myapp-dev \
  --association-id a-xxxxx

# Must match pod namespace!
# Update Terraform to use correct namespace parameter
```

#### 3. Service Account Name Mismatch

**Symptom**: Pod can't assume role despite correct namespace

**Fix**:
```bash
# Check what service account pod is using
kubectl get pod <pod-name> -n <namespace> -o yaml | grep serviceAccount

# Check what SA the association expects
aws eks describe-pod-identity-association ...

# Update Helm values to use correct service account name
```

#### 4. Role Trust Policy Issues

**Symptom**: `An error occurred (InvalidIdentityToken)`

**Fix**: Ensure role trust policy uses `pods.eks.amazonaws.com`:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "pods.eks.amazonaws.com"
  },
  "Action": [
    "sts:AssumeRole",
    "sts:TagSession"
  ]
}
```

NOT the old OIDC format!

## Migration from IRSA to Pod Identity

If you have existing IRSA setup, follow these steps:

### 1. Update Trust Policy

Change from OIDC to Pod Identity service:

**Before (IRSA)**:
```json
{
  "Principal": {
    "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks..."
  },
  "Action": "sts:AssumeRoleWithWebIdentity"
}
```

**After (Pod Identity)**:
```json
{
  "Principal": {
    "Service": "pods.eks.amazonaws.com"
  },
  "Action": ["sts:AssumeRole", "sts:TagSession"]
}
```

### 2. Create Pod Identity Association

```hcl
resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.app.arn
}
```

### 3. Remove IRSA Annotation

**Before**:
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/MyRole
```

**After**:
```yaml
serviceAccount:
  name: my-app
  # No annotations needed!
```

### 4. Ensure Pod Identity Agent Running

```bash
kubectl get daemonset -n kube-system eks-pod-identity-agent
```

### 5. Restart Pods

```bash
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

### 6. Verify

```bash
# Check pod logs for successful AWS API calls
kubectl logs <pod-name> -n <namespace>

# Should NOT see IRSA/OIDC errors
# Should see successful AWS SDK calls
```

## Best Practices

1. **Always use Pod Identity for new deployments**
2. **Match namespace** between association and Helm release
3. **Match service account name** in association and pod spec
4. **Don't add role-arn annotations** (Pod Identity doesn't use them)
5. **Ensure Pod Identity Agent is running** before deploying workloads
6. **Use descriptive role names** for easier debugging

## References

- [AWS Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [EKS Pod Identity vs IRSA Comparison](https://aws.amazon.com/blogs/containers/amazon-eks-pod-identity-a-new-way-for-applications-on-eks-to-obtain-iam-credentials/)
- [Terraform EKS Module Pod Identity Support](https://github.com/terraform-aws-modules/terraform-aws-eks)

## Summary

✅ Pod Identity is simpler, faster, and AWS-recommended
✅ No OIDC provider or complex annotations
✅ Direct AWS-managed authentication
✅ Better performance and easier debugging
✅ Used by default in this infrastructure

For troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#karpenter-issues).
