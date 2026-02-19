#!/bin/bash
#
# Display ArgoCD credentials for all running clusters.
# Automatically detects which EKS clusters are available.
#
# Usage: ./scripts/argocd-credentials.sh

set -euo pipefail

# Cluster name -> ArgoCD URL mapping
declare -A ARGOCD_URLS=(
  [myapp-dev]="http://argocd.dev.example.com"
  [myapp-prod]="http://argocd.prod.example.com"
)

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1" >&2; }
section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

section "ArgoCD Credentials"

found=0

for context in $(kubectl config get-contexts -o name 2>/dev/null); do
  # Extract cluster name from context (handles both ARN and alias formats)
  cluster_name=$(echo "$context" | grep -oE 'myapp-(dev|prod)' || true)
  [[ -z "$cluster_name" ]] && continue

  url="${ARGOCD_URLS[$cluster_name]:-}"
  [[ -z "$url" ]] && continue
  # Prevent processing the same cluster twice (ARN + alias)
  unset "ARGOCD_URLS[$cluster_name]"

  # Check if cluster is reachable
  if ! kubectl cluster-info --context "$context" &>/dev/null; then
    warn "$cluster_name — not reachable, skipping"
    continue
  fi

  # Get password
  password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    --context "$context" \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

  if [[ -n "$password" ]]; then
    info "$cluster_name"
    echo "    URL:      $url"
    echo "    Username: admin"
    echo "    Password: $password"
    found=$((found + 1))
  else
    warn "$cluster_name — ArgoCD secret not found"
  fi

  echo ""
done

if [[ $found -eq 0 ]]; then
  err "No running clusters with ArgoCD found"
  echo "  Make sure kubectl is configured: ./scripts/configure-kubectl.sh"
  exit 1
fi
