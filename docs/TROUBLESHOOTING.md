# Troubleshooting Guide

Common issues and solutions for EKS infrastructure deployment.

## Table of Contents

- [Deployment Issues](#deployment-issues)
- [Cluster Access](#cluster-access)
- [ArgoCD Issues](#argocd-issues)
- [Karpenter Issues](#karpenter-issues)
- [Networking Issues](#networking-issues)

---

## Deployment Issues

### Terraform State Lock

**Symptom**: `Error acquiring the state lock`

**Cause**: Previous terraform run didn't clean up properly

**Solution**:
```bash
# Check current locks
aws dynamodb scan --table-name terraform-locks-ACCOUNT_ID

# Force unlock (use with caution!)
cd path/to/module
terragrunt force-unlock LOCK_ID
```

### Terragrunt Dependency Errors

**Symptom**: `dependency output not found`

**Cause**: Mock outputs mismatch or missing outputs

**Solution**:
```bash
# Ensure dependency module is deployed first
cd ../dependency-module
terragrunt apply

# Then retry your module
cd ../your-module
terragrunt apply
```

---

## Cluster Access

### Kubernetes Cluster Unreachable

**Symptom**: `dial tcp: i/o timeout` or `connection refused`

**Cause**: Cluster endpoint is private-only or security groups blocking access

**Solution**:
```bash
# Check cluster endpoint access
aws eks describe-cluster --name myapp-dev \
  --query 'cluster.resourcesVpcConfig.{public:endpointPublicAccess,private:endpointPrivateAccess}'

# Should show: {"public": true, "private": true}

# Update kubeconfig
aws eks update-kubeconfig --name myapp-dev --region us-east-1

# Test connection
kubectl cluster-info
```

### Unauthorized / Access Denied

**Symptom**: `error: You must be logged in to the server (Unauthorized)`

**Cause**: IAM user/role not granted cluster access

**Solution**:
```bash
# Check your identity
aws sts get-caller-identity

# EKS uses API authentication mode - check access entries
aws eks list-access-entries --cluster-name myapp-dev

# Grant yourself access (if you're cluster creator, you should already have access)
# Otherwise, ask cluster admin to add you
```

---

## ArgoCD Issues

### Applications Not Syncing

**Symptom**: Applications stuck in "Unknown" or "OutOfSync" status

**Cause**: Missing GitHub PAT or incorrect repository URL

**Solution**:
```bash
# 1. Check GitHub PAT secret exists
kubectl get secret -n argocd github-token

# If missing, create it
kubectl -n argocd create secret generic github-token \
  --from-literal=token=YOUR_GITHUB_PAT

# 2. Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-repo-server | tail -50
kubectl logs -n argocd deployment/argocd-application-controller | tail -50

# 3. Manually sync application
kubectl patch application myapp-dev -n argocd --type merge \
  -p '{"operation": {"sync": {}}}'

# Or via ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080 and click "Sync"
```

### ApplicationSet Not Creating Applications

**Symptom**: ApplicationSet exists but no Applications created

**Cause**: ApplicationSet generator not matching or syntax error

**Solution**:
```bash
# Check ApplicationSet
kubectl get applicationset -n argocd myapp-dev-envs -o yaml

# Check events
kubectl describe applicationset myapp-dev-envs -n argocd

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-applicationset-controller
```

### Can't Access ArgoCD UI

**Symptom**: Port forward works but can't login

**Solution**:
```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Reset password if needed
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {"admin.password": "'$(htpasswd -nbBC 10 "" YOUR_NEW_PASSWORD | tr -d ':\n' | sed 's/$2y/$2a/')'"}}'
```

---

## Karpenter Issues

### Karpenter Not Scaling Nodes

**Symptom**: Pods stay in Pending but no nodes created

**Cause**: Karpenter misconfiguration or insufficient permissions

**Solution**:
```bash
# 1. Check Karpenter logs
kubectl logs -n karpenter deployment/karpenter -f

# 2. Check NodePool exists
kubectl get nodepool
kubectl describe nodepool default

# 3. Check EC2NodeClass
kubectl get ec2nodeclass
kubectl describe ec2nodeclass default

# 4. Create test deployment to trigger scaling
kubectl create deployment test --image=nginx --replicas=10

# 5. Check pending pods
kubectl get pods -A | grep Pending
kubectl describe pod <pending-pod>
```

### Karpenter Webhook Timeout

**Symptom**: `failed calling webhook: Post "https://aws-load-balancer-webhook-service.kube-system.svc:443": no endpoints available`

**Cause**: Karpenter deployed before AWS Load Balancer Controller ready

**Solution**:
This is fixed by the dependency in `prod/karpenter/terragrunt.hcl`. If you still see this:

```bash
# Verify AWS LBC is running
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# If not running, deploy it first
cd prod/aws-load-balancer-controller
terragrunt apply

# Then redeploy Karpenter
cd ../karpenter
terragrunt apply
```

### Nodes Not Joining Cluster

**Symptom**: Karpenter creates EC2 instances but they don't join cluster

**Cause**: Security groups, IAM role, or network misconfiguration

**Solution**:
```bash
# Check EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=default" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,LaunchTime]'

# Check instance logs
aws ec2 get-console-output --instance-id i-xxxxx

# Check security groups
kubectl get ec2nodeclass default -o jsonpath='{.spec.securityGroupSelectorTerms}'
```

---

## Networking Issues

### Ingress Not Creating ALB

**Symptom**: Ingress created but no ALB provisioned

**Cause**: AWS Load Balancer Controller not running or service annotations missing

**Solution**:
```bash
# 1. Check AWS LBC is running
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# 2. Check ingress
kubectl get ingress -A
kubectl describe ingress <ingress-name> -n <namespace>

# 3. Check service annotations
kubectl get svc -n ingress-nginx ingress-nginx-controller -o yaml | grep annotations -A 10
```

### Pods Can't Reach Internet

**Symptom**: Pods timeout when accessing external URLs

**Cause**: NAT Gateway or security group issue

**Solution**:
```bash
# Check NAT Gateway
aws ec2 describe-nat-gateways \
  --filter "Name=tag:Environment,Values=dev" \
  --query 'NatGateways[].[NatGatewayId,State]'

# Check route tables
aws ec2 describe-route-tables \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'RouteTables[].Routes'

# Test from pod
kubectl run test --image=curlimages/curl --rm -it -- curl -I https://google.com
```

---

## Performance Issues

### Slow Apply Times

**Symptom**: Terragrunt apply takes very long

**Cause**: Large dependency graph or slow providers

**Solution**:
```bash
# Run with parallelism
terragrunt run --all --parallelism=10 -- apply

# Use targeted applies when possible
terragrunt apply --target=specific_resource
```

### Helm Release Timeouts

**Symptom**: `timed out waiting for the condition`

**Cause**: Pods not starting due to resource constraints or image pull issues

**Solution**:
```bash
# Check pod status
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Increase timeout in Helm release
# In Terraform module, set: timeout = 900 (15 minutes)
```

---

## Emergency Procedures

### Roll Back Deployment

```bash
# Terraform
cd module/path
terragrunt plan -destroy
terragrunt destroy

# Helm
helm rollback <release-name> -n <namespace>

# ArgoCD
kubectl patch application <app-name> -n argocd --type merge \
  -p '{"spec":{"source":{"targetRevision":"previous-commit-sha"}}}'
```

### Force Unlock All States

```bash
# List all lock IDs
aws dynamodb scan --table-name terraform-locks-ACCOUNT_ID \
  --query 'Items[].LockID.S'

# Force unlock each (DANGEROUS - only if you're sure no one else is running)
cd module/path
terragrunt force-unlock <LOCK_ID>
```

---

## Getting Help

If you're still stuck:

1. Check AWS CloudWatch logs for the relevant service
2. Review Kubernetes events: `kubectl get events -A --sort-by='.lastTimestamp'`
3. Check Terraform state: `terragrunt show`
4. Review the [Architecture documentation](ARCHITECTURE.md)

## Common Error Messages

| Error | Solution |
|-------|----------|
| `AccessDenied: Not authorized to perform sts:AssumeRole` | Check IAM role trust policy and permissions |
| `InvalidParameterException: The platform AWS is not supported` | Wrong region or AZ - use us-east-1 |
| `ResourceAlreadyExists` | Resource already exists, import it or delete manually |
| `DependencyViolation` | Resources still attached, delete them first |
| `InvalidParameterValue: The subnet ID 'subnet-xxx' does not exist` | VPC not deployed yet, check dependencies |
