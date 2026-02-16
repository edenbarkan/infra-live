# ArgoCD Setup & GitOps Configuration

Guide for configuring ArgoCD and ApplicationSets for GitOps workflow.

## Overview

This infrastructure uses ArgoCD ApplicationSets to automatically manage application deployments across environments.

**Key Features:**
- Automatic application generation per environment
- Git-based source of truth
- Automated sync for dev/staging, manual for prod
- Separation of concerns (infra vs apps)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     GitHub Repos                         │
├───────────────────┬─────────────────────────────────────┤
│  app-source       │  helm-charts                        │
│  (Application)    │  (Helm Charts + Config)             │
│                   │                                     │
│  • Source code    │  • Generic Helm chart               │
│  • Dockerfile     │  • Environment overlays             │
│  • CI/CD          │    - dev/values.yaml                │
│                   │    - staging/values.yaml            │
│                   │    - production/values.yaml         │
└──────┬────────────┴────────┬────────────────────────────┘
       │                     │
       │ Push                │ Watch
       ▼                     ▼
┌─────────────┐      ┌──────────────┐
│   GitHub    │      │   ArgoCD     │
│   Actions   ├─────>│ ApplicationSet│
│             │      │              │
│ Build image │      │ Generates:   │
│ Push to ECR │      │ • myapp-dev  │
│ Update      │      │ • myapp-stg  │
│ helm-charts │      │ • myapp-prod │
└─────────────┘      └──────┬───────┘
                            │
                            ▼
                     ┌─────────────┐
                     │  Kubernetes │
                     │  Clusters   │
                     └─────────────┘
```

## ApplicationSet Configuration

### Dev Cluster ApplicationSet

Creates 2 applications: `myapp-dev` and `myapp-staging`

**File**: `modules/argocd/applicationset-dev.yaml`

**Features:**
- Automated sync with prune and self-heal
- Watches `main` branch
- Uses environment-specific value files

### Prod Cluster ApplicationSet

Creates 1 application: `myapp-production`

**File**: `modules/argocd/applicationset-prod.yaml`

**Features:**
- **Manual sync only** (requires approval)
- Watches `main` branch
- Production-specific configurations

## GitOps Workflow

### 1. Developer Workflow

```bash
# 1. Make changes to application
cd app-source
git checkout -b feature/new-feature
# ... make changes ...
git commit -m "feat: add new feature"
git push origin feature/new-feature

# 2. Create PR and merge to main
# GitHub Actions automatically:
# - Builds Docker image
# - Pushes to ECR as myapp:abc1234
# - Updates helm-charts repo with new tag

# 3. ArgoCD detects change and syncs
# - Dev: Auto-deploys immediately
# - Staging: Requires manual promotion
# - Prod: Requires manual sync in UI
```

### 2. Promoting to Staging

```bash
cd helm-charts
git pull

# Update staging values
yq e '.image.tag = "abc1234"' -i apps/myapp/overlays/staging/values.yaml

git commit -m "promote: myapp abc1234 to staging"
git push

# ArgoCD auto-syncs staging namespace
```

### 3. Promoting to Production

```bash
cd helm-charts

# Update production values
yq e '.image.tag = "abc1234"' -i apps/myapp/overlays/production/values.yaml

git commit -m "promote: myapp abc1234 to production"
git push

# Manual sync required in ArgoCD UI:
# 1. Open ArgoCD UI
# 2. Find myapp-production application
# 3. Click "Sync" and "Synchronize"
```

## GitHub PAT Setup

ArgoCD needs a GitHub Personal Access Token to access private repositories.

### Create PAT

1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token (classic)
3. Scopes needed:
   - `repo` (full control of private repositories)
4. Copy token (you won't see it again!)

### Configure in Cluster

```bash
# Dev cluster
aws eks update-kubeconfig --name myapp-dev --region us-east-1
kubectl -n argocd create secret generic github-token \
  --from-literal=token=ghp_xxxxxxxxxxxxxxxxxxxx

# Prod cluster
aws eks update-kubeconfig --name myapp-prod --region us-east-1
kubectl -n argocd create secret generic github-token \
  --from-literal=token=ghp_xxxxxxxxxxxxxxxxxxxx
```

### Verify

```bash
# Check secret exists
kubectl get secret -n argocd github-token

# Check ArgoCD can access repo
kubectl logs -n argocd deployment/argocd-repo-server | grep -i auth
```

## ArgoCD UI Access

### Port Forward

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Get Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Login

- URL: https://localhost:8080
- Username: `admin`
- Password: (from above command)

## Verifying ApplicationSets

### Check ApplicationSets

```bash
# List ApplicationSets
kubectl get applicationset -n argocd

# Expected output for dev:
# NAME              AGE
# myapp-dev-envs    5m

# Expected output for prod:
# NAME              AGE
# myapp-prod-envs   5m
```

### Check Generated Applications

```bash
# List Applications
kubectl get application -n argocd

# Expected for dev cluster:
# NAME           SYNC STATUS   HEALTH STATUS
# myapp-dev      Synced        Healthy
# myapp-staging  Synced        Healthy

# Expected for prod cluster:
# NAME              SYNC STATUS   HEALTH STATUS
# myapp-production  OutOfSync     Healthy  (manual sync required)
```

### View Application Details

```bash
kubectl describe application myapp-dev -n argocd
```

## Customizing ApplicationSets

### Add New Environment

Edit the ApplicationSet YAML to add a new environment:

```yaml
spec:
  generators:
  - list:
      elements:
      - env: dev
        namespace: dev
      - env: staging
        namespace: staging
      - env: qa          # NEW
        namespace: qa    # NEW
```

Apply the change:

```bash
kubectl apply -f modules/argocd/applicationset-dev.yaml
```

### Change Sync Policy

For dev (auto-sync):

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

For prod (manual sync):

```yaml
syncPolicy:
  # No automated section = manual sync required
  syncOptions:
  - CreateNamespace=true
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md#argocd-issues) for ArgoCD-specific issues.

### Quick Checks

```bash
# Check ArgoCD health
kubectl get pods -n argocd
kubectl get applications -n argocd

# Check ApplicationSet controller
kubectl logs -n argocd deployment/argocd-applicationset-controller

# Force sync
kubectl patch application myapp-dev -n argocd --type merge \
  -p '{"operation": {"sync": {}}}'
```

## Best Practices

1. **Always use GitOps**: Never `kubectl apply` directly in prod
2. **Test in dev first**: Validate changes before promoting
3. **Use manual sync for prod**: Requires conscious approval
4. **Keep secrets in Secrets Manager**: Use External Secrets Operator
5. **Tag images with git SHA**: Enables traceability
6. **Review before promoting**: Check logs, metrics before staging/prod

## Next Steps

1. ✅ Configure GitHub PAT
2. ✅ Verify ApplicationSets created Applications
3. Push a change and watch it deploy to dev
4. Practice promoting to staging/prod
5. Set up monitoring and alerting

For more details, see the main [README](../README.md).
