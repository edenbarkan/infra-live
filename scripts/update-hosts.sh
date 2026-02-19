#!/bin/bash
#
# Update /etc/hosts with ALB IPs for all running app environments.
# Automatically detects which EKS clusters are available.
#
# Usage: sudo ./scripts/update-hosts.sh

set -euo pipefail

# --- Config ---
MARKER="# myapp-eks-environments"

# Cluster name -> hostnames mapping
declare -A CLUSTER_HOSTS=(
  [myapp-dev]="myapp.dev.example.com myapp.staging.example.com argocd.dev.example.com"
  [myapp-prod]="myapp.example.com argocd.prod.example.com"
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

# --- Require root ---
if [[ $EUID -ne 0 ]]; then
  err "This script must be run with sudo"
  echo "  sudo $0"
  exit 1
fi

section "Detecting running clusters"

# Clean old entries
sed -i '' "/$MARKER/d" /etc/hosts
sed -i '' '/myapp\.dev\.example\.com/d' /etc/hosts
sed -i '' '/myapp\.staging\.example\.com/d' /etc/hosts
sed -i '' '/myapp\.example\.com/d' /etc/hosts
sed -i '' '/argocd\.dev\.example\.com/d' /etc/hosts
sed -i '' '/argocd\.prod\.example\.com/d' /etc/hosts

found=0
urls=()

for context in $(kubectl config get-contexts -o name 2>/dev/null); do
  # Extract cluster name from context (handles both ARN and alias formats)
  cluster_name=$(echo "$context" | grep -oE 'myapp-(dev|prod)' || true)
  [[ -z "$cluster_name" ]] && continue

  hosts="${CLUSTER_HOSTS[$cluster_name]:-}"
  [[ -z "$hosts" ]] && continue
  # Prevent processing the same cluster twice (ARN + alias)
  unset "CLUSTER_HOSTS[$cluster_name]"

  # Check if cluster is reachable
  if ! kubectl cluster-info --context "$context" &>/dev/null; then
    warn "$cluster_name — not reachable, skipping"
    continue
  fi

  info "$cluster_name is running"

  # Get ALB DNS from ingress
  alb=$(kubectl get ingress alb-to-nginx -n ingress-nginx --context "$context" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

  if [[ -z "$alb" ]]; then
    warn "$cluster_name — ALB not found, skipping"
    continue
  fi

  # Resolve to IP
  ip=$(dig +short "$alb" | head -1)
  if [[ -z "$ip" ]]; then
    warn "$cluster_name — could not resolve $alb"
    continue
  fi

  info "$cluster_name → $ip"

  # Add to /etc/hosts
  echo "${ip}  ${hosts} ${MARKER}" >> /etc/hosts
  found=$((found + 1))

  # Collect URLs for display
  for h in $hosts; do
    urls+=("http://$h")
  done
done

if [[ $found -eq 0 ]]; then
  err "No running clusters found. Is kubectl configured?"
  exit 1
fi

section "Updating /etc/hosts"

info "Updated /etc/hosts:"
grep "$MARKER" /etc/hosts | while read -r line; do
  echo "    $line"
done

# Flush macOS DNS cache so changes take effect immediately
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true
info "DNS cache flushed"

section "Browser access"
for url in "${urls[@]}"; do
  echo "  $url"
done
echo ""
