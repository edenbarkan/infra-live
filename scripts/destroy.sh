#!/bin/bash
#
# 🧹 EKS Infrastructure Destroy Script
# Usage: ALLOW_DESTROY=true ./destroy.sh [environment]
#   environment: dev, prod, all (default: all)
#
# Non-interactive mode: AUTO_APPROVE=true ALLOW_DESTROY=true ./destroy.sh all
#
# ⚠️  WARNING: This will DELETE all resources and data!
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

confirm_destruction() {
    local env=$1

    section "⚠️  DESTRUCTIVE OPERATION WARNING"

    warn "You are about to DESTROY the $env environment!"
    echo ""
    echo "This will delete:"
    echo "   🗑️  EKS cluster (myapp-$env)"
    echo "   🗑️  All running applications"
    echo "   🗑️  VPC and networking"
    echo "   🗑️  All infrastructure components"
    echo ""
    warn "This action CANNOT be undone!"
    echo ""

    if [ "${AUTO_APPROVE:-false}" = "true" ]; then
        warn "AUTO_APPROVE=true: Skipping confirmation prompt"
        info "Proceeding with destruction..."
        return
    fi

    read -p "Type '$env' to confirm destruction: " confirmation

    if [ "$confirmation" != "$env" ]; then
        error "Confirmation failed. Aborting."
        exit 1
    fi

    info "Proceeding with destruction..."
}

destroy_environment() {
    local env=$1

    confirm_destruction "$env"

    section "Destroying $env Environment"

    cd "$env"

    info "Removing all modules..."
    warn "This may take 10-15 minutes..."

    # Destroy in reverse order
    # Using new terragrunt v0.99+ syntax
    terragrunt run --all --non-interactive -- destroy

    cd ..
    info "✅ $env environment destroyed"
}

destroy_ecr() {
    section "ECR Repository"

    warn "Do you want to destroy the ECR repository?"
    warn "This will delete ALL container images!"
    echo ""

    local response="n"
    if [ "${AUTO_APPROVE:-false}" = "true" ]; then
        warn "AUTO_APPROVE=true: Auto-destroying ECR"
        response="y"
    else
        read -p "Destroy ECR? [y/N]: " response
    fi

    if [[ "$response" =~ ^[Yy]$ ]]; then
        cd ecr
        info "Destroying ECR repository..."
        terragrunt destroy -auto-approve
        cd ..
        info "✅ ECR destroyed"
    else
        info "Skipping ECR destruction"
    fi
}

destroy_bootstrap() {
    section "Bootstrap Resources"

    warn "Do you want to destroy bootstrap resources (S3 + DynamoDB)?"
    warn "This will delete the Terraform state storage!"
    warn "⚠️  Only do this if you're completely cleaning up!"
    echo ""

    local response="n"
    if [ "${AUTO_APPROVE:-false}" = "true" ]; then
        warn "AUTO_APPROVE=true: Auto-destroying bootstrap"
        response="y"
    else
        read -p "Destroy bootstrap? [y/N]: " response
    fi

    if [[ "$response" =~ ^[Yy]$ ]]; then
        cd bootstrap
        info "Destroying S3 bucket and DynamoDB table..."
        terragrunt destroy -auto-approve
        cd ..
        info "✅ Bootstrap destroyed"
    else
        info "Skipping bootstrap destruction"
        info "State remains in S3 bucket: myproject-tfstate"
    fi
}

cleanup_local_files() {
    section "Cleaning Local Files"

    info "Removing Terraform/Terragrunt cache directories..."

    # Remove .terraform directories
    find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true

    # Remove .terragrunt-cache directories
    find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true

    # Remove lock files
    find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true

    info "✅ Local cache cleaned"
}

show_summary() {
    section "🧹 Cleanup Complete"

    echo ""
    info "Resources have been destroyed."
    echo ""
    warn "Remember to:"
    echo "   • Check AWS Console for any orphaned resources"
    echo "   • Verify no unexpected charges"
    echo "   • Clean up any manual resources"
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
    echo "  ║   🧹 EKS Infrastructure Cleanup       ║"
    echo "  ╚════════════════════════════════════════╝"
    echo ""

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run: aws configure"
        exit 1
    fi

    local account=$(aws sts get-caller-identity --query Account --output text)
    local user=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)

    info "AWS Account: $account"
    info "AWS User: $user"

    case "$environment" in
        dev)
            destroy_environment "dev"
            ;;
        prod)
            destroy_environment "prod"
            ;;
        all)
            # Destroy in reverse order
            destroy_environment "prod"
            destroy_environment "dev"
            destroy_ecr
            destroy_bootstrap
            ;;
        *)
            error "Invalid environment: $environment"
            error "Usage: ALLOW_DESTROY=true ./destroy.sh [dev|prod|all]"
            exit 1
            ;;
    esac

    cleanup_local_files
    show_summary
}

# Safety check
if [ "${ALLOW_DESTROY:-false}" != "true" ]; then
    echo ""
    error "╔════════════════════════════════════════════════════╗"
    error "║  ⚠️  SAFETY CHECK: Destruction not allowed!       ║"
    error "╚════════════════════════════════════════════════════╝"
    echo ""
    warn "This script will DELETE all infrastructure."
    warn "To proceed, run:"
    echo ""
    echo "  ALLOW_DESTROY=true ./destroy.sh $*"
    echo ""
    exit 1
fi

# Run main
main "$@"
