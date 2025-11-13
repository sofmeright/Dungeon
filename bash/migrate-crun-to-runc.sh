#!/bin/bash
set -euo pipefail

# Runtime Migration Script: crun → runc (CVE-2025-31133/52565/52881 fix)
# Migrates CRI-O container runtime from vulnerable crun 1.24 to patched runc 1.3.3
# Performs rolling node migration with graceful pod eviction

RUNC_VERSION="1.3.3-0ubuntu1~24.04.2"
CONTROL_PLANE_NODES=("dungeon-map-001" "dungeon-map-002" "dungeon-map-003" "dungeon-map-004" "dungeon-map-005")
WORKER_NODES=("dungeon-chest-001" "dungeon-chest-002" "dungeon-chest-003" "dungeon-chest-004" "dungeon-chest-005")
ALL_NODES=("${CONTROL_PLANE_NODES[@]}" "${WORKER_NODES[@]}")

# Configuration
DRAIN_TIMEOUT="300s"  # 5 minutes for pod eviction
DRAIN_GRACE_PERIOD="30"  # 30 seconds for graceful termination
POD_READINESS_WAIT="60"  # Wait 60s for pods to stabilize after node uncordon

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

error() {
    echo -e "${RED}[$(date ='%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
    exit 1
}

# Preflight checks
preflight_checks() {
    log "Starting preflight checks..."

    # Check kubectl access
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot access Kubernetes cluster. Check kubeconfig."
    fi

    # Check SSH access to all nodes
    for node in "${ALL_NODES[@]}"; do
        if ! ssh -o ConnectTimeout=5 "$node" "echo ok" &>/dev/null; then
            error "Cannot SSH to $node"
        fi
    done

    # Verify current runtime
    log "Checking current runtime on nodes..."
    for node in "${ALL_NODES[@]}"; do
        current_runtime=$(ssh "$node" "grep '^runtime_path' /etc/crio/crio.conf.d/10-crio.conf | head -1 | awk '{print \$3}' | tr -d '\"'")
        if [[ "$current_runtime" != "/usr/libexec/crio/crun" ]]; then
            warn "Node $node already using: $current_runtime (expected crun)"
        fi
    done

    # Check if runc package is available
    if ! ssh "${ALL_NODES[0]}" "apt-cache show runc=$RUNC_VERSION" &>/dev/null; then
        error "runc version $RUNC_VERSION not available in apt repos"
    fi

    log "✓ All preflight checks passed"
}

# Migrate a single node
migrate_node() {
    local node=$1
    log "========================================"
    log "Migrating node: $node"
    log "========================================"

    # Step 1: Cordon node (prevent new pods from scheduling)
    log "[$node] Cordoning node..."
    if ! kubectl cordon "$node"; then
        error "Failed to cordon $node"
    fi

    # Step 2: Drain node (gracefully evict pods)
    log "[$node] Draining node (timeout: $DRAIN_TIMEOUT, grace: ${DRAIN_GRACE_PERIOD}s)..."
    if ! kubectl drain "$node" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --force \
        --grace-period="$DRAIN_GRACE_PERIOD" \
        --timeout="$DRAIN_TIMEOUT"; then
        warn "Drain had issues, but continuing..."
    fi

    # Step 3: Install patched runc
    log "[$node] Installing runc $RUNC_VERSION..."
    if ! ssh "$node" "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y runc=$RUNC_VERSION"; then
        error "Failed to install runc on $node"
    fi

    # Verify installation
    local installed_version
    installed_version=$(ssh "$node" "/usr/bin/runc --version | grep 'runc version' | awk '{print \$3}'")
    if [[ "$installed_version" != "1.3.3" ]]; then
        error "runc installation verification failed on $node (got: $installed_version)"
    fi
    log "[$node] ✓ runc 1.3.3 installed"

    # Step 4: Update CRI-O config to use runc
    log "[$node] Updating CRI-O configuration..."
    ssh "$node" "sudo sed -i 's|runtime_path = \"/usr/libexec/crio/crun\"|runtime_path = \"/usr/bin/runc\"|g' /etc/crio/crio.conf.d/10-crio.conf"
    ssh "$node" "sudo sed -i 's|runtime_path = \"/usr/libexec/crio/crun\"|runtime_path = \"/usr/bin/runc\"|g' /etc/crio/crio.conf.d/10-runtime.conf 2>/dev/null || true"

    # Verify config change
    local new_runtime
    new_runtime=$(ssh "$node" "grep '^runtime_path' /etc/crio/crio.conf.d/10-crio.conf | head -1 | awk '{print \$3}' | tr -d '\"'")
    if [[ "$new_runtime" != "/usr/bin/runc" ]]; then
        error "Config update failed on $node (got: $new_runtime)"
    fi
    log "[$node] ✓ CRI-O config updated to use runc"

    # Step 5: Restart CRI-O
    log "[$node] Restarting CRI-O service..."
    if ! ssh "$node" "sudo systemctl restart crio"; then
        error "Failed to restart CRI-O on $node"
    fi

    # Wait for CRI-O to be ready
    sleep 5
    if ! ssh "$node" "sudo systemctl is-active crio" &>/dev/null; then
        error "CRI-O is not running on $node after restart"
    fi
    log "[$node] ✓ CRI-O restarted successfully"

    # Step 6: Uncordon node (allow pod scheduling)
    log "[$node] Uncordoning node..."
    if ! kubectl uncordon "$node"; then
        error "Failed to uncordon $node"
    fi

    # Step 7: Wait for node to be Ready
    log "[$node] Waiting for node to become Ready..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if kubectl get node "$node" | grep -q "Ready"; then
            break
        fi
        retries=$((retries - 1))
        sleep 2
    done

    if [ $retries -eq 0 ]; then
        error "Node $node did not become Ready within 60 seconds"
    fi
    log "[$node] ✓ Node is Ready"

    # Step 8: Wait for pods to stabilize
    log "[$node] Waiting ${POD_READINESS_WAIT}s for pods to stabilize..."
    sleep "$POD_READINESS_WAIT"

    # Check for pod issues
    local notready_pods
    notready_pods=$(kubectl get pods -A --field-selector spec.nodeName="$node" --no-headers 2>/dev/null | grep -v "Running\|Completed\|Succeeded" | wc -l)
    if [ "$notready_pods" -gt 0 ]; then
        warn "Node $node has $notready_pods pods not in Running state"
        kubectl get pods -A --field-selector spec.nodeName="$node" | grep -v "Running\|Completed\|Succeeded" || true
    fi

    log "[$node] ✓ Migration complete"
}

# Main migration process
main() {
    echo "========================================"
    echo "CRI-O Runtime Migration: crun → runc"
    echo "Target runc version: $RUNC_VERSION"
    echo "Total nodes: ${#ALL_NODES[@]}"
    echo "========================================"
    echo ""

    # Run preflight checks
    preflight_checks
    echo ""

    # Confirm before proceeding
    read -p "Proceed with migration? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Migration cancelled by user"
        exit 0
    fi
    echo ""

    # Migrate worker nodes first (safer, control plane stays operational)
    log "Phase 1: Migrating worker nodes..."
    for node in "${WORKER_NODES[@]}"; do
        migrate_node "$node"
        echo ""
    done

    log "Phase 1 complete: All worker nodes migrated"
    echo ""

    # Migrate control plane nodes one at a time
    log "Phase 2: Migrating control plane nodes..."
    warn "Control plane migration starting - API may experience brief interruptions"
    for node in "${CONTROL_PLANE_NODES[@]}"; do
        migrate_node "$node"
        echo ""
        log "Waiting 30s before next control plane node..."
        sleep 30
    done

    log "Phase 2 complete: All control plane nodes migrated"
    echo ""

    # Final verification
    log "Performing final verification..."
    log "Checking runtime on all nodes..."
    for node in "${ALL_NODES[@]}"; do
        runtime=$(ssh "$node" "grep '^runtime_path' /etc/crio/crio.conf.d/10-crio.conf | head -1 | awk '{print \$3}' | tr -d '\"'")
        version=$(ssh "$node" "/usr/bin/runc --version 2>/dev/null | grep 'runc version' | awk '{print \$3}'")
        if [[ "$runtime" == "/usr/bin/runc" ]] && [[ "$version" == "1.3.3" ]]; then
            log "  $node: ✓ runc $version"
        else
            error "  $node: ✗ Unexpected config - runtime: $runtime, version: $version"
        fi
    done

    echo ""
    log "========================================"
    log "Migration complete!"
    log "All nodes now using runc 1.3.3"
    log "CVE-2025-31133, CVE-2025-52565, CVE-2025-52881 mitigated"
    log "========================================"

    # Summary
    echo ""
    log "Post-migration checklist:"
    log "1. Verify pods are running: kubectl get pods -A"
    log "2. Check for CrashLoopBackOff: kubectl get pods -A | grep -v Running"
    log "3. Review node status: kubectl get nodes"
    log "4. Monitor logs: kubectl logs -n <namespace> <pod>"
}

# Run migration
main
