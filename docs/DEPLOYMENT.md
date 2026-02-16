# Deployment Guide

Complete guide for deploying the infrastructure from scratch.

## Prerequisites

- **Tools**: terragrunt (≥0.99), terraform (≥1.5), kubectl, awscli
- **AWS Account**: Active account with admin access
- **Permissions**: IAM user/role with EKS, VPC, EC2, IAM permissions

## Installation

```bash
# macOS
brew install terragrunt terraform kubectl awscli

# Verify
terragrunt --version
terraform --version
kubectl version --client
aws --version
```

## AWS Configuration

```bash
# Option 1: AWS CLI configuration
aws configure

# Option 2: AWS SSO
aws sso login --profile your-profile
export AWS_PROFILE=your-profile
```

## Quick Deployment

### Deploy Everything (Recommended)

```bash
./scripts/deploy.sh all
```

This will:
1. Create S3 bucket and DynamoDB table for state
2. Create ECR repository
3. Deploy dev environment (VPC, EKS, all addons)
4. Deploy prod environment (VPC, EKS, all addons)
5. Configure kubectl contexts
6. Display ArgoCD credentials

**Time**: ~60 minutes total

### Deploy Specific Environment

```bash
# Dev only
./scripts/deploy.sh dev

# Prod only
./scripts/deploy.sh prod
```

## Manual Deployment

If you prefer step-by-step deployment:

### 1. Bootstrap

```bash
cd bootstrap
terragrunt apply
```

Creates:
- S3 bucket: `terraform-state-<account-id>`
- DynamoDB table: `terraform-locks-<account-id>`

### 2. ECR Repository

```bash
cd ecr
terragrunt apply
```

### 3. Dev Environment

```bash
cd dev
terragrunt run --all -- apply
```

Order (automatic via dependencies):
1. VPC
2. EKS cluster
3. Addons (parallel): Karpenter, AWS LBC, External Secrets
4. Ingress-NGINX
5. ArgoCD

### 4. Prod Environment

```bash
cd prod
terragrunt run --all -- apply
```

## Post-Deployment

### Verify Cluster Health

```bash
# Update kubeconfig
aws eks update-kubeconfig --name myapp-dev --region us-east-1
aws eks update-kubeconfig --name myapp-prod --region us-east-1

# Check nodes
kubectl get nodes
kubectl get nodes --context arn:aws:eks:us-east-1:ACCOUNT:cluster/myapp-prod

# Check pods
kubectl get pods -A
```

### Access ArgoCD

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser
open https://localhost:8080
# Username: admin
# Password: <from above>
```

### Configure GitHub PAT (Required for ArgoCD)

ArgoCD needs a GitHub Personal Access Token to access the helm-charts repo:

```bash
# Create secret
kubectl -n argocd create secret generic github-token \
  --from-literal=token=YOUR_GITHUB_PAT

# For prod cluster
kubectl --context arn:aws:eks:us-east-1:ACCOUNT:cluster/myapp-prod \
  -n argocd create secret generic github-token \
  --from-literal=token=YOUR_GITHUB_PAT
```

## Cleanup

### Destroy Specific Environment

```bash
ALLOW_DESTROY=true ./scripts/destroy.sh dev
ALLOW_DESTROY=true ./scripts/destroy.sh prod
```

### Destroy Everything

```bash
ALLOW_DESTROY=true ./scripts/destroy.sh all
```

**Note**: The `ALLOW_DESTROY` flag is required as a safety measure.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## Cost Optimization

- **Dev**: Uses spot instances via Karpenter (~60% cost savings)
- **Prod**: Uses on-demand for reliability
- Karpenter automatically scales nodes based on workload
- Consider using Savings Plans or Reserved Instances for production

## Next Steps

1. ✅ Deploy infrastructure
2. Configure GitHub PAT for ArgoCD
3. Set up CI/CD pipeline (see repo README)
4. Deploy your applications via ArgoCD

For GitOps setup, see [ARGOCD-SETUP.md](ARGOCD-SETUP.md).
