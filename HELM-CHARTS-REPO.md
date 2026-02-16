# Helm Charts Repository - Complete Setup Guide

This repository contains the generic Helm chart and per-application configurations used by ArgoCD.

## Repository Structure

```
helm-charts/
├── README.md
├── charts/
│   └── generic-app/              # Reusable Helm chart
│       ├── Chart.yaml
│       ├── values.yaml          # Default values
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── hpa.yaml
│           ├── pdb.yaml
│           ├── serviceaccount.yaml
│           └── externalsecret.yaml
│
├── apps/
│   └── myapp/
│       ├── base/
│       │   └── values.yaml      # Shared across all environments
│       └── overlays/
│           ├── dev/
│           │   └── values.yaml
│           ├── staging/
│           │   └── values.yaml
│           └── production/
│               └── values.yaml
│
└── argocd-apps/
    ├── dev-applicationset.yaml
    └── prod-applicationset.yaml
```

---

## Setup Instructions

### 1. Create the Repository

```bash
cd /Users/Eden/Desktop/projects/for-project-circle
mkdir -p helm-charts
cd helm-charts
git init
```

### 2. Create Chart Structure

```bash
mkdir -p charts/generic-app/templates
mkdir -p apps/myapp/{base,overlays/{dev,staging,production}}
mkdir -p argocd-apps
```

---

## File Contents

### `charts/generic-app/Chart.yaml`

```yaml
apiVersion: v2
name: generic-app
description: Generic Helm chart for containerized applications
type: application
version: 1.0.0
appVersion: "1.0"
```

### `charts/generic-app/values.yaml`

<details>
<summary>Click to see full values.yaml (200+ lines)</summary>

```yaml
# Default values for generic-app
replicaCount: 2

image:
  repository: ""  # REQUIRED - set per app
  tag: "latest"
  pullPolicy: IfNotPresent

nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: true
  className: "nginx"
  annotations: {}
  hosts:
    - host: ""  # REQUIRED - set per env
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

# Security Context
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL

# Topology Spread for HA
topologySpread:
  enabled: true
  maxSkew: 1
  topologyKey: "topology.kubernetes.io/zone"
  whenUnsatisfiable: DoNotSchedule

# Graceful Shutdown
terminationGracePeriodSeconds: 30
preStopSleepSeconds: 5

# Health Checks
healthCheck:
  liveness:
    path: /health
    port: 8080
    initialDelaySeconds: 15
    periodSeconds: 10
  readiness:
    path: /ready
    port: 8080
    initialDelaySeconds: 5
    periodSeconds: 5

# Horizontal Pod Autoscaler
autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

# Pod Disruption Budget
pdb:
  enabled: true
  minAvailable: 1

# External Secrets
externalSecret:
  enabled: false
  secretStoreName: "aws-secrets-manager"
  refreshInterval: "1h"
  data: []

env: []
envFrom: []
podAnnotations: {}
nodeSelector: {}
tolerations: []
affinity: {}
```

</details>

### `charts/generic-app/templates/deployment.yaml`

See the full template in the original plan above (section 5.3).

### `apps/myapp/base/values.yaml`

```yaml
# Shared values across all environments
image:
  repository: "123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp"

service:
  port: 80
  targetPort: 8080

healthCheck:
  liveness:
    path: /health
    port: 8080
  readiness:
    path: /ready
    port: 8080
```

### `apps/myapp/overlays/dev/values.yaml`

```yaml
image:
  tag: "latest"  # Updated by CI

replicaCount: 1

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 250m
    memory: 128Mi

ingress:
  hosts:
    - host: myapp.dev.example.com
      paths:
        - path: /
          pathType: Prefix

externalSecret:
  enabled: true
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: dev/myapp/db-password

topologySpread:
  enabled: false  # Single AZ OK for dev
```

### `apps/myapp/overlays/production/values.yaml`

```yaml
image:
  tag: "v1.0.0"  # Semantic versioning in prod

replicaCount: 3

# Guaranteed QoS: requests == limits
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 250m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 15
  targetCPUUtilizationPercentage: 70

pdb:
  minAvailable: 2

ingress:
  hosts:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix

externalSecret:
  enabled: true
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: production/myapp/db-password
```

### `argocd-apps/dev-applicationset.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-dev-envs
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
            namespace: dev
          - env: staging
            namespace: staging
  template:
    metadata:
      name: "myapp-{{env}}"
    spec:
      project: dev
      source:
        repoURL: https://github.com/edenbarkan/helm-charts.git
        targetRevision: main
        path: charts/generic-app
        helm:
          valueFiles:
            - ../../apps/myapp/base/values.yaml
            - ../../apps/myapp/overlays/{{env}}/values.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### `argocd-apps/prod-applicationset.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-prod
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: production
            namespace: production
  template:
    metadata:
      name: "myapp-production"
    spec:
      project: prod
      source:
        repoURL: https://github.com/edenbarkan/helm-charts.git
        targetRevision: main
        path: charts/generic-app
        helm:
          valueFiles:
            - ../../apps/myapp/base/values.yaml
            - ../../apps/myapp/overlays/production/values.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: production
      syncPolicy:
        # NO automated block - manual sync required for prod
        syncOptions:
          - CreateNamespace=true
```

---

## Deploy to ArgoCD

```bash
# After infrastructure is deployed, apply ApplicationSets

# For dev cluster
aws eks update-kubeconfig --name myapp-dev --region us-east-1
kubectl apply -f argocd-apps/dev-applicationset.yaml

# For prod cluster
aws eks update-kubeconfig --name myapp-prod --region us-east-1
kubectl apply -f argocd-apps/prod-applicationset.yaml
```

---

## Complete Setup Script

```bash
#!/bin/bash
# setup-helm-charts.sh

set -e

REPO_URL="https://github.com/edenbarkan/helm-charts.git"

# Create repository
cd /Users/Eden/Desktop/projects/for-project-circle
mkdir -p helm-charts && cd helm-charts
git init

# Create structure
mkdir -p charts/generic-app/templates
mkdir -p apps/myapp/{base,overlays/{dev,staging,production}}
mkdir -p argocd-apps

echo "✅ Repository structure created"
echo "📝 Now copy the file contents from HELM-CHARTS-REPO.md"
echo "🚀 Then: git add . && git commit -m 'Initial commit' && git push"
```

---

## Testing Locally

```bash
# Test rendering dev environment
helm template myapp charts/generic-app \
  -f apps/myapp/base/values.yaml \
  -f apps/myapp/overlays/dev/values.yaml

# Test rendering production
helm template myapp charts/generic-app \
  -f apps/myapp/base/values.yaml \
  -f apps/myapp/overlays/production/values.yaml
```

---

**Next:** See `APP-SOURCE-REPO.md` for the application repository setup.
