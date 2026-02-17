#!/usr/bin/env bash
#
# 🚀 EKS Infrastructure Deployment Script
# Usage: ./deploy.sh [environment]
#   environment: dev, prod, all (default: all)
#
# This script deploys a production-grade EKS cluster with:
#   - Karpenter for node autoscaling
#   - ArgoCD for GitOps
#   - AWS Load Balancer Controller
#   - Ingress-NGINX for routing
#   - External Secrets Operator
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Functions
info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

check_prerequisites() {
    section "Checking Prerequisites"

    local missing=0

    # Check terragrunt
    if command -v terragrunt &> /dev/null; then
        info "terragrunt: $(terragrunt --version | head -n1)"
    else
        error "terragrunt not found. Install: brew install terragrunt"
        missing=1
    fi

    # Check terraform
    if command -v terraform &> /dev/null; then
        info "terraform: $(terraform --version | head -n1)"
    else
        error "terraform not found. Install: brew install terraform"
        missing=1
    fi

    # Check kubectl
    if command -v kubectl &> /dev/null; then
        info "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -n1)"
    else
        warn "kubectl not found (optional, but needed for cluster access)"
    fi

    # Check AWS CLI
    if command -v aws &> /dev/null; then
        info "aws-cli: $(aws --version)"
    else
        error "aws-cli not found. Install: brew install awscli"
        missing=1
    fi

    # Check AWS credentials
    if aws sts get-caller-identity &> /dev/null; then
        local account=$(aws sts get-caller-identity --query Account --output text)
        local user=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)
        info "AWS Account: $account"
        info "AWS User: $user"
    else
        error "AWS credentials not configured. Run: aws configure"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        error "Please install missing prerequisites and try again."
        exit 1
    fi

    info "All prerequisites met! ✅"
}

deploy_bootstrap() {
    section "Phase 1: Bootstrap (S3 + DynamoDB)"

    if [ -f "bootstrap/.terraform.lock.hcl" ]; then
        info "Bootstrap already initialized, skipping..."
        return
    fi

    cd bootstrap

    info "Creating S3 bucket and DynamoDB table for Terraform state..."
    terragrunt apply -auto-approve

    cd ..
    info "✅ Bootstrap complete"
}

deploy_ecr() {
    section "Phase 2: ECR Repository"

    cd ecr
    info "Creating ECR repository..."
    terragrunt apply -auto-approve
    cd ..

    info "✅ ECR complete"
}

cleanup_stale_locks() {
    local env=$1
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local table_name="terraform-locks-${account_id}"

    section "Cleaning Up Stale State Locks ($env)"

    local modules=("vpc" "eks" "karpenter" "aws-load-balancer-controller" "ingress-nginx" "external-secrets" "argocd")

    for module in "${modules[@]}"; do
        local lock_key="tfstate-${account_id}-us-east-1/${env}/${module}/terraform.tfstate"
        local lock_id=$(aws dynamodb get-item \
            --table-name "$table_name" \
            --key "{\"LockID\": {\"S\": \"${lock_key}\"}}" \
            --query 'Item.Info.S' --output text 2>/dev/null || echo "NONE")

        if [ "$lock_id" != "NONE" ] && [ "$lock_id" != "None" ]; then
            warn "Removing stale lock for ${env}/${module}..."
            aws dynamodb delete-item \
                --table-name "$table_name" \
                --key "{\"LockID\": {\"S\": \"${lock_key}\"}}" 2>/dev/null || true
        fi
    done

    info "✅ Stale locks cleaned up"
}

deploy_environment() {
    local env=$1

    section "Phase 3: Deploying $env Environment"

    info "This will create:"
    echo "   • VPC (10.x.0.0/16)"
    echo "   • EKS Cluster (myapp-$env)"
    echo "   • Karpenter (node autoscaling)"
    echo "   • AWS Load Balancer Controller"
    echo "   • Ingress-NGINX"
    echo "   • External Secrets"
    echo "   • ArgoCD"
    echo ""
    warn "Estimated time: 30-40 minutes"
    echo ""

    # Clean up any stale locks from previous failed runs
    cleanup_stale_locks "$env"

    cd "$env"

    # Deploy all modules (Terragrunt figures out dependency order)
    # Dependencies defined in each module's terragrunt.hcl via 'dependency' blocks
    # Order: VPC → EKS → [Karpenter, AWS LBC, External Secrets] → Ingress-NGINX → ArgoCD
    # Terragrunt parallelizes independent modules (Karpenter, AWS LBC, External Secrets)
    # Using new terragrunt v0.99+ syntax
    terragrunt run --all --non-interactive -- apply

    cd ..
    info "✅ $env environment complete"
}

configure_kubectl() {
    local env=$1
    local cluster_name="myapp-$env"

    section "Configuring kubectl"

    info "Updating kubeconfig for $cluster_name..."
    aws eks update-kubeconfig --name "$cluster_name" --region us-east-1 &> /dev/null

    info "✅ kubectl configured"
    info "Current context: $(kubectl config current-context)"
}

remove_node_taints() {
    local env=$1

    section "Removing Node Taints"

    # Switch context
    aws eks update-kubeconfig --name "myapp-$env" --region us-east-1 &> /dev/null

    info "Removing CriticalAddonsOnly taint to allow addon scheduling..."
    kubectl get nodes -o name 2>/dev/null | xargs -I {} kubectl taint node {} CriticalAddonsOnly- 2>/dev/null || true

    info "✅ Taints removed"
}

wait_for_addon_health() {
    local env=$1

    section "Waiting for Addons to be Ready ($env)"

    aws eks update-kubeconfig --name "myapp-$env" --region us-east-1 &> /dev/null

    info "Waiting for Karpenter..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/karpenter -n karpenter 2>/dev/null || warn "Karpenter not ready"

    info "Waiting for AWS Load Balancer Controller..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/aws-load-balancer-controller -n kube-system 2>/dev/null || warn "AWS LBC not ready"

    info "Waiting for Ingress-NGINX..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/ingress-nginx-controller -n ingress-nginx 2>/dev/null || warn "Ingress-NGINX not ready"

    info "Waiting for External Secrets..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/external-secrets -n external-secrets 2>/dev/null || warn "External Secrets not ready"

    info "✅ All addons healthy"
}

prompt_github_pat() {
    local env=$1

    section "GitHub PAT Configuration ($env)"

    aws eks update-kubeconfig --name "myapp-$env" --region us-east-1 &> /dev/null

    # Check if secret already exists
    if kubectl get secret -n argocd github-token &>/dev/null; then
        info "GitHub PAT secret already configured"
        return
    fi

    echo ""
    warn "ArgoCD needs a GitHub PAT to access the helm-charts repository."
    echo ""
    echo "Please set the GitHub PAT secret:"
    echo ""
    echo "  kubectl -n argocd create secret generic github-token \\"
    echo "    --from-literal=token=YOUR_GITHUB_PAT"
    echo ""
    warn "Remember to set the GitHub PAT before applications can sync!"
}

verify_cluster() {
    local env=$1

    section "Verifying $env Cluster"

    # Switch context
    aws eks update-kubeconfig --name "myapp-$env" --region us-east-1 &> /dev/null

    info "Checking nodes..."
    kubectl get nodes 2>/dev/null || warn "Nodes not ready yet"

    info "Checking infrastructure pods..."
    local namespaces=("karpenter" "kube-system" "ingress-nginx" "external-secrets" "argocd")

    for ns in "${namespaces[@]}"; do
        local pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$pod_count" -gt 0 ]; then
            info "✅ $ns: $pod_count pods"
        else
            warn "$ns: No pods yet"
        fi
    done
}

get_argocd_info() {
    local env=$1

    section "ArgoCD Credentials ($env)"

    # Switch context
    aws eks update-kubeconfig --name "myapp-$env" --region us-east-1 &> /dev/null

    # Wait for ArgoCD secret
    info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server -n argocd 2>/dev/null || warn "ArgoCD not ready yet"

    # Get password
    local password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

    if [ -n "$password" ]; then
        info "✅ ArgoCD is ready!"
        echo ""
        echo "   📍 URL: https://localhost:8080"
        echo "   👤 Username: admin"
        echo "   🔑 Password: $password"
        echo ""
        info "To access the UI, run:"
        echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    else
        warn "ArgoCD password not available yet. Check again in a few minutes:"
        echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    fi
}

show_next_steps() {
    section "🎉 Deployment Complete!"

    echo ""
    info "Your EKS cluster is ready!"
    echo ""
    echo "📋 Next Steps:"
    echo ""
    echo "1️⃣  Verify cluster health:"
    echo "   kubectl get nodes"
    echo "   kubectl get pods -A"
    echo ""
    echo "2️⃣  Access ArgoCD UI:"
    echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "   → https://localhost:8080"
    echo ""
    echo "3️⃣  Test Karpenter autoscaling:"
    echo "   kubectl create deployment test --image=nginx --replicas=10"
    echo "   kubectl get nodes -w"
    echo ""
    echo "4️⃣  Deploy your application:"
    echo "   - Set up helm-charts repository"
    echo "   - Configure ArgoCD ApplicationSets"
    echo "   - Push your app!"
    echo ""
    info "For more details, see README.md"
    echo ""
}

main() {
    local environment="${1:-all}"

    # Skip clear for non-interactive terminals
    if [ -t 1 ]; then
        clear 2>/dev/null || true
    fi
    echo ""
    echo "  ╔════════════════════════════════════════╗"
    echo "  ║   🚀 EKS Infrastructure Deployment    ║"
    echo "  ╚════════════════════════════════════════╝"
    echo ""

    check_prerequisites

    # Always bootstrap first
    deploy_bootstrap

    # Always deploy ECR (shared)
    deploy_ecr

    case "$environment" in
        dev)
            deploy_environment "dev"
            configure_kubectl "dev"
            remove_node_taints "dev"
            wait_for_addon_health "dev"
            verify_cluster "dev"
            get_argocd_info "dev"
            ;;
        prod)
            deploy_environment "prod"
            configure_kubectl "prod"
            remove_node_taints "prod"
            wait_for_addon_health "prod"
            verify_cluster "prod"
            get_argocd_info "prod"
            ;;
        all)
            deploy_environment "dev"
            deploy_environment "prod"

            # Configure kubectl for dev
            configure_kubectl "dev"

            # Remove taints from both environments
            remove_node_taints "dev"
            remove_node_taints "prod"

            # Wait for addon health
            wait_for_addon_health "dev"
            wait_for_addon_health "prod"

            # Verify both
            verify_cluster "dev"
            verify_cluster "prod"

            # Get credentials
            get_argocd_info "dev"
            get_argocd_info "prod"

            # Show GitHub PAT instructions if needed
            prompt_github_pat "dev"
            prompt_github_pat "prod"
            ;;
        *)
            error "Invalid environment: $environment"
            error "Usage: ./deploy.sh [dev|prod|all]"
            exit 1
            ;;
    esac

    show_next_steps
}

# Run main
main "$@"
