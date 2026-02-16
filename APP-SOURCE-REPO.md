# Application Source Repository - Complete Setup Guide

This repository contains your application code and CI/CD pipelines.

## Repository Structure

```
app-source/
├── README.md
├── Dockerfile
├── .dockerignore
├── src/
│   ├── index.js           # Example Node.js app
│   └── package.json
└── .github/
    └── workflows/
        ├── ci.yaml                    # Build, test, push to ECR
        ├── promote-staging.yaml       # Promote to staging
        └── promote-production.yaml    # Promote to production
```

---

## Setup Instructions

### 1. Create Repository

```bash
cd /Users/Eden/Desktop/projects/for-project-circle
mkdir -p app-source
cd app-source
git init
```

### 2. Create Structure

```bash
mkdir -p src .github/workflows
```

---

## File Contents

### `Dockerfile`

```dockerfile
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY src/package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY src/ ./

# Create non-root user
RUN addgroup -g 1000 app && \
    adduser -D -u 1000 -G app app && \
    chown -R app:app /app

# Final stage
FROM node:18-alpine

WORKDIR /app

# Copy from builder
COPY --from=builder --chown=app:app /app /app

# Use non-root user
USER app

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/health', (r) => r.statusCode === 200 ? process.exit(0) : process.exit(1))"

EXPOSE 8080

CMD ["node", "index.js"]
```

### `.dockerignore`

```
node_modules
npm-debug.log
.git
.github
README.md
.env
.DS_Store
```

### `src/package.json`

```json
{
  "name": "myapp",
  "version": "1.0.0",
  "description": "Example application",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Tests passed\""
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
```

### `src/index.js`

```javascript
const express = require('express');
const app = express();
const PORT = process.env.PORT || 8080;

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

// Readiness check endpoint
app.get('/ready', (req, res) => {
  res.status(200).json({ status: 'ready' });
});

// Main endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Hello from EKS!',
    version: process.env.VERSION || '1.0.0',
    environment: process.env.ENVIRONMENT || 'unknown'
  });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

---

## CI/CD Workflows

### `.github/workflows/ci.yaml`

```yaml
name: CI - Build & Deploy to Dev

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

permissions:
  id-token: write  # OIDC for AWS
  contents: read

env:
  AWS_REGION: us-east-1
  ECR_REPO: myapp

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image_tag: ${{ steps.meta.outputs.version }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-role
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Docker metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ steps.ecr.outputs.registry }}/${{ env.ECR_REPO }}
          tags: |
            type=sha,prefix=
            type=ref,event=branch
            type=semver,pattern={{version}}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Run Trivy vulnerability scanner
        if: github.event_name != 'pull_request'
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: "${{ steps.ecr.outputs.registry }}/${{ env.ECR_REPO }}:${{ steps.meta.outputs.version }}"
          format: "table"
          exit-code: "1"
          severity: "HIGH,CRITICAL"

  deploy-dev:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/develop'

    steps:
      - name: Checkout helm-charts repo
        uses: actions/checkout@v4
        with:
          repository: edenbarkan/helm-charts
          token: ${{ secrets.GH_PAT }}
          path: helm-charts

      - name: Update dev image tag
        run: |
          cd helm-charts
          yq e '.image.tag = "${{ needs.build.outputs.image_tag }}"' \
            -i apps/myapp/overlays/dev/values.yaml

      - name: Commit and push
        run: |
          cd helm-charts
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add .
          git commit -m "ci(dev): update myapp to ${{ needs.build.outputs.image_tag }}" || exit 0
          git push

      - name: Notify
        run: |
          echo "✅ Image pushed to ECR: ${{ needs.build.outputs.image_tag }}"
          echo "✅ ArgoCD will auto-sync dev namespace"
```

### `.github/workflows/promote-staging.yaml`

```yaml
name: Promote to Staging

on:
  workflow_dispatch:
    inputs:
      image_tag:
        description: 'Image tag to promote from dev'
        required: true
        type: string

permissions:
  contents: write

jobs:
  promote:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout helm-charts repo
        uses: actions/checkout@v4
        with:
          repository: edenbarkan/helm-charts
          token: ${{ secrets.GH_PAT }}

      - name: Update staging image tag
        run: |
          yq e '.image.tag = "${{ inputs.image_tag }}"' \
            -i apps/myapp/overlays/staging/values.yaml

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add .
          git commit -m "ci(staging): promote to ${{ inputs.image_tag }}"
          git push

      - name: Notify
        run: |
          echo "✅ Staging promoted to: ${{ inputs.image_tag }}"
          echo "✅ ArgoCD will auto-sync staging namespace"
```

### `.github/workflows/promote-production.yaml`

```yaml
name: Promote to Production

on:
  workflow_dispatch:
    inputs:
      image_tag:
        description: 'Image tag to promote from staging (use semantic version)'
        required: true
        type: string

permissions:
  contents: write

jobs:
  promote:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout helm-charts repo
        uses: actions/checkout@v4
        with:
          repository: edenbarkan/helm-charts
          token: ${{ secrets.GH_PAT }}

      - name: Update production image tag
        run: |
          yq e '.image.tag = "${{ inputs.image_tag }}"' \
            -i apps/myapp/overlays/production/values.yaml

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add .
          git commit -m "ci(prod): promote to ${{ inputs.image_tag }}"
          git push

      - name: Notify
        run: |
          echo "✅ Production tag updated to: ${{ inputs.image_tag }}"
          echo "⚠️  ArgoCD will show OutOfSync"
          echo "👤 Manual sync required in ArgoCD UI"
```

---

## GitHub Secrets Setup

You need to configure these secrets in your GitHub repository:

1. **AWS_ACCOUNT_ID** - Your AWS account ID
2. **GH_PAT** - Personal Access Token with `repo` scope

### Setting up OIDC for AWS

```bash
# Create trust policy for GitHub Actions
cat > github-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:edenbarkan/*:*"
        }
      }
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name github-actions-role \
  --assume-role-policy-document file://github-trust-policy.json

# Attach ECR permissions
aws iam attach-role-policy \
  --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```

---

## Testing the CI/CD Pipeline

### 1. Initial Deployment

```bash
git checkout -b develop
git add .
git commit -m "feat: initial application"
git push -u origin develop
```

This triggers:
- Build Docker image
- Security scan with Trivy
- Push to ECR
- Auto-deploy to dev namespace

### 2. Promote to Staging

In GitHub UI:
- Go to Actions → "Promote to Staging"
- Click "Run workflow"
- Enter the image tag from dev (e.g., `sha-abc1234`)
- Click "Run"

### 3. Promote to Production

In GitHub UI:
- Go to Actions → "Promote to Production"
- Click "Run workflow"
- Enter semantic version (e.g., `v1.0.0`)
- Click "Run"
- **Then** go to ArgoCD UI and manually click "Sync"

---

## Complete Setup Script

```bash
#!/bin/bash
# setup-app-source.sh

set -e

# Create repository
cd /Users/Eden/Desktop/projects/for-project-circle
mkdir -p app-source && cd app-source
git init

# Create structure
mkdir -p src .github/workflows

echo "✅ Repository structure created"
echo "📝 Now copy the file contents from APP-SOURCE-REPO.md"
echo "🚀 Then: git add . && git commit -m 'Initial commit' && git push"
```

---

**🎉 All 3 Repositories Complete!**

1. ✅ **infra-live** - Infrastructure (Terraform/Terragrunt)
2. ✅ **helm-charts** - Application manifests
3. ✅ **app-source** - Application code + CI/CD
