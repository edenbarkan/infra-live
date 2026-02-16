#!/bin/bash
#
# Configure kubectl for EKS cluster access
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

section "Configuring kubectl for EKS"

# Configure kubectl for dev cluster
info "Updating kubeconfig for myapp-dev cluster..."
aws eks update-kubeconfig --name myapp-dev --region us-east-1

info "✅ kubectl configured!"
echo ""
info "Current context: $(kubectl config current-context)"
echo ""

section "Verifying Cluster Access"

info "Checking cluster info..."
kubectl cluster-info

echo ""
info "Checking nodes..."
kubectl get nodes

echo ""
info "Checking all pods..."
kubectl get pods -A

echo ""
section "ArgoCD Credentials"

info "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd 2>/dev/null || echo "ArgoCD not ready yet, check again in a few minutes"

# Get ArgoCD password
PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -n "$PASSWORD" ]; then
    echo ""
    info "✅ ArgoCD is ready!"
    echo ""
    echo "   📍 URL: https://localhost:8080"
    echo "   👤 Username: admin"
    echo "   🔑 Password: $PASSWORD"
    echo ""
    info "To access the UI, run:"
    echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
else
    echo ""
    info "ArgoCD password not available yet. Try this command in a few minutes:"
    echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
fi

echo ""
section "Next Steps"
echo ""
echo "1️⃣  Deploy ArgoCD ApplicationSets:"
echo "   cd ~/Desktop/projects/for-project-circle/helm-charts"
echo "   kubectl apply -f argocd-apps/dev-applicationset.yaml"
echo ""
echo "2️⃣  Watch ArgoCD sync your apps:"
echo "   kubectl get applications -n argocd -w"
echo ""
echo "3️⃣  Test Karpenter autoscaling:"
echo "   kubectl create deployment test --image=nginx --replicas=10"
echo "   kubectl get nodes -w"
echo ""
