# Architecture Overview

Detailed architecture and component breakdown for the EKS infrastructure.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Cloud                            │
│                                                             │
│  ┌──────────────────┐          ┌──────────────────┐        │
│  │   Dev Cluster    │          │   Prod Cluster   │        │
│  │   myapp-dev      │          │   myapp-prod     │        │
│  │   10.0.0.0/16    │          │   10.1.0.0/16    │        │
│  └────────┬─────────┘          └────────┬─────────┘        │
│           │                             │                   │
│           └──────────┬──────────────────┘                   │
│                      │                                      │
│           ┌──────────▼──────────┐                          │
│           │  Shared Resources   │                          │
│           │  • ECR              │                          │
│           │  • S3 (state)       │                          │
│           │  • DynamoDB (locks) │                          │
│           │  • Secrets Manager  │                          │
│           └─────────────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

## Infrastructure Components

### 1. Networking (VPC)

**Dev**: `10.0.0.0/16`
- 3 Public Subnets (ALB, NAT Gateway)
- 3 Private Subnets (EKS nodes)
- 1 NAT Gateway (cost optimization)
- Internet Gateway

**Prod**: `10.1.0.0/16`
- 3 Public Subnets
- 3 Private Subnets
- 1 NAT Gateway (cost optimization)
- Internet Gateway

### 2. EKS Cluster

**Version**: 1.30

**Authentication**:
- API authentication mode (replaces aws-auth ConfigMap)
- EKS Pod Identity for workload authentication

**Addons**:
- CoreDNS (DNS resolution)
- kube-proxy (network routing)
- VPC CNI (networking with prefix delegation)
- EKS Pod Identity Agent (IAM role assumption)

**Node Groups**:
- **System nodes**: 2×t3.medium (for critical addons)
  - Tainted with `CriticalAddonsOnly:NoSchedule`
  - Tolerations configured for system components
- **Karpenter nodes**: Auto-scaled based on workload

**Endpoint Access**:
- Public + Private (allows deployment from anywhere)
- Private access for nodes/pods via VPC

### 3. Karpenter (Node Autoscaling)

**Purpose**: Efficient, fast node autoscaling

**Components**:
- Controller (Pod Identity role)
- Node IAM role (for EC2 instances)
- SQS queue (spot interruption handling)
- EventBridge rules (spot termination warnings)

**Dev Configuration**:
- Instance families: t3, t3a, t2
- Capacity type: Spot (60% cost savings)
- CPU limit: 20 vCPUs

**Prod Configuration**:
- Instance families: m5, m6i, c5
- Capacity type: Spot + On-demand (cost optimized with fallback)
- CPU limit: 20 vCPUs

**NodePool**:
- Consolidation policy: WhenUnderutilized
- Expire after: 720h (30 days)

### 4. AWS Load Balancer Controller

**Purpose**: Provisions AWS ALBs/NLBs for Kubernetes services

**Components**:
- Controller deployment (2 replicas for HA)
- IAM role (Pod Identity)
- Webhook (validates Ingress/Service resources)

**Features**:
- Creates ALB for Ingress resources
- Manages target groups
- Integrates with AWS WAF
- Supports SSL/TLS termination

### 5. Ingress-NGINX

**Purpose**: HTTP/HTTPS routing inside cluster

**Configuration**:
- Service type: NodePort (ALB connects to it)
- Replicas: 1 (dev), 2 (prod)
- Resources: 100m-500m CPU, 128Mi-512Mi memory
- IngressClass: nginx

**Flow**:
```
Internet → ALB → NodePort → Ingress-NGINX → App Pods
```

### 6. External Secrets

**Purpose**: Sync secrets from AWS Secrets Manager to Kubernetes

**Components**:
- Controller deployment
- IAM role (Pod Identity) with Secrets Manager access
- ClusterSecretStore (cluster-wide secret store)

**Usage**:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
spec:
  secretStoreRef:
    name: aws-secrets-manager
  target:
    name: app-secrets
  data:
  - secretKey: DATABASE_URL
    remoteRef:
      key: dev/myapp/database
```

### 7. ArgoCD (GitOps)

**Purpose**: Continuous deployment from Git

**Components**:
- Server (UI + API)
- Repo server (Git repository access)
- Application controller (sync logic)
- ApplicationSet controller (multi-app generation)

**Projects**:
- `dev`: For dev and staging namespaces
- `prod`: For production namespace

**ApplicationSets**:
- Dev cluster: Generates myapp-dev, myapp-staging
- Prod cluster: Generates myapp-production

**Sync Policies**:
- Dev/Staging: Automated (prune + self-heal)
- Production: Manual (requires approval)

## Data Flow

### Application Deployment Flow

```
Developer pushes to develop
  ↓
GitHub Actions: Lint → Test → Build → Trivy scan → Push to ECR
  ↓
CI updates helm-charts dev overlay → ArgoCD auto-syncs dev

Developer merges PR (develop → main)
  ↓
GitHub Actions: Build → Trivy scan → Push to ECR
  ↓
CI updates helm-charts staging overlay → ArgoCD auto-syncs staging

Manual workflow dispatch (production)
  ↓
CI updates helm-charts production overlay
  ↓
Manual sync required in ArgoCD UI
```

### Traffic Flow

```
User Request
  ↓
AWS Route 53 (DNS)
  ↓
Application Load Balancer (ALB)
  ↓
NodePort Service (Ingress-NGINX)
  ↓
Ingress-NGINX Controller
  ↓
Service
  ↓
Pod
```

### Node Scaling Flow

```
Pod pending (no resources)
  ↓
Karpenter detects pending pod
  ↓
Karpenter provisions EC2 instance
  ↓
Instance joins cluster (Pod Identity auth)
  ↓
Pod scheduled on new node
  ↓
After idle period: Karpenter consolidates/terminates
```

## Security Architecture

### Network Security

- Private subnets for all EKS nodes
- Public subnets only for ALB and NAT Gateway
- Security groups restrict traffic:
  - Node ↔ Control plane
  - Node ↔ Node
  - ALB → Nodes (specific ports)

### IAM Security

- **EKS Pod Identity**: Modern AWS-managed authentication
- **Least privilege**: Each component has minimal IAM permissions
- **No static credentials**: All authentication via IAM roles
- **Audit trail**: CloudTrail logs all IAM actions

### Secret Management

- **External Secrets Operator**: Syncs from AWS Secrets Manager to K8s Secrets
- **End-to-end flow**: AWS Secrets Manager → ESO (ClusterSecretStore) → ExternalSecret → K8s Secret → Pod envFrom
- **No secrets in Git**: Applications reference secrets by name in helm overlays
- **IAM isolation**: Dev cluster can only read `dev/*` and `staging/*` secrets; prod can only read `production/*`
- **Rotation**: Update in Secrets Manager, ESO syncs on `refreshInterval` (1h), restart pods to pick up new values

## State Management

### Terraform State

- **Backend**: S3 bucket
- **Locking**: DynamoDB table
- **Encryption**: AES-256 server-side encryption
- **Versioning**: Enabled for rollback capability

### Terragrunt

- **DRY**: Shared configuration in root terragrunt.hcl
- **Dependencies**: Automatic ordering (VPC → EKS → Addons)
- **Environments**: dev/ and prod/ directories
- **Modules**: Reusable in modules/ directory

## Cost Optimization

### Compute

- **Dev**: Spot instances via Karpenter (60% savings)
- **Prod**: Spot + On-demand (cost optimized with reliability fallback)
- **System nodes**: Fixed 2×t3.medium (minimal baseline)
- **Karpenter**: Automatic consolidation when underutilized

### Network

- **Dev**: 1 NAT Gateway (~$32/month)
- **Prod**: 1 NAT Gateway (~$32/month)
- Both use single NAT for cost optimization

### Storage

- **EBS volumes**: gp3 (cheaper than gp2)
- **S3**: Terraform state only (minimal cost)

**Estimated Monthly Costs**:
- Dev: ~$165 (spot instances, single NAT)
- Prod: ~$165 (spot + on-demand, single NAT)
- Total: ~$330/month

## Scalability

### Horizontal Scaling

- **Pods**: HPA (Horizontal Pod Autoscaler)
- **Nodes**: Karpenter (fast, efficient)
- **ALB**: AWS-managed, auto-scales

### Limits

- **Dev**: 20 vCPU limit (cost control)
- **Prod**: 20 vCPU limit (cost control)
- **Service quotas**: AWS account limits apply

## Disaster Recovery

### Backup

- **Terraform state**: S3 with versioning
- **Kubernetes manifests**: Git (source of truth)
- **Secrets**: Stored in AWS Secrets Manager
- **Application data**: Application-specific backup strategy

### Recovery

1. Redeploy infrastructure: `./scripts/deploy.sh all`
2. ArgoCD syncs applications from Git
3. External Secrets syncs secrets from Secrets Manager
4. Applications restore data from backups

**RTO**: ~1 hour (infrastructure deployment)
**RPO**: Near-zero (Git-based, no data loss)

## Monitoring & Observability

### Built-in

- **CloudWatch**: EKS control plane logs
- **Kubernetes events**: `kubectl get events`
- **ArgoCD UI**: Application health and sync status

### Recommended Additions

- **Prometheus**: Metrics collection
- **Grafana**: Dashboards
- **Loki**: Log aggregation
- **Alertmanager**: Alerting rules

## Next Steps

For deployment instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).
For troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
For GitOps setup, see [ARGOCD-SETUP.md](ARGOCD-SETUP.md).
