#!/usr/bin/env bash
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
    echo -e "${RED}[✗]${NC} $1" >&2
}

section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# --- Require root ---
if [[ $EUID -ne 0 ]]; then
    error "This script must be run with sudo"
    echo "  sudo $0"
    exit 1
fi

# --- Check prerequisites ---
section "Checking Prerequisites"

missing=0

if command -v kubectl &> /dev/null; then
    info "kubectl: found"
else
    error "kubectl not found. Install: brew install kubectl"
    missing=1
fi

if command -v dig &> /dev/null; then
    info "dig: found"
else
    error "dig not found. Install: brew install bind"
    missing=1
fi

if [ $missing -eq 1 ]; then
    error "Please install missing prerequisites and try again."
    exit 1
fi

# --- Detect and resolve clusters ---
section "Detecting Running Clusters"

new_entries=()
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

    # Collect entry (don't write yet — only write if at least one cluster resolves)
    new_entries+=("${ip}  ${hosts} ${MARKER}")

    for h in $hosts; do
        urls+=("http://$h")
    done
done

if [[ ${#new_entries[@]} -eq 0 ]]; then
    error "No running clusters found. Is kubectl configured?"
    exit 1
fi

# --- Update /etc/hosts (only after successful resolution) ---
section "Updating /etc/hosts"

# Remove old entries
sed -i '' "/$MARKER/d" /etc/hosts
sed -i '' '/myapp\.dev\.example\.com/d' /etc/hosts
sed -i '' '/myapp\.staging\.example\.com/d' /etc/hosts
sed -i '' '/myapp\.example\.com/d' /etc/hosts
sed -i '' '/argocd\.dev\.example\.com/d' /etc/hosts
sed -i '' '/argocd\.prod\.example\.com/d' /etc/hosts

# Write new entries
for entry in "${new_entries[@]}"; do
    echo "$entry" >> /etc/hosts
done

info "Updated /etc/hosts:"
grep "$MARKER" /etc/hosts | while read -r line; do
    echo "    $line"
done

# Flush macOS DNS cache so changes take effect immediately
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true
info "DNS cache flushed"

section "Browser Access"
for url in "${urls[@]}"; do
    echo "  $url"
done
echo ""
