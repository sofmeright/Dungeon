#!/bin/bash
################################################################################
# Configure Kubelet Graceful Shutdown
#
# This script configures kubelet's graceful shutdown feature on a node.
# Kubelet will automatically handle pod eviction during system shutdown/reboot.
#
# Usage:
#   ./k8s-configure-graceful-shutdown.sh <node-hostname>
################################################################################

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <node-hostname>"
    echo "Example: $0 dungeon-chest-001"
    exit 1
fi

NODE=$1
KUBELET_CONFIG="/var/lib/kubelet/config.yaml"

echo "Configuring graceful shutdown on $NODE..."

# Configure graceful shutdown on remote node
ssh "$NODE" bash <<'REMOTE_CONFIG'
set -e

KUBELET_CONFIG="/var/lib/kubelet/config.yaml"

echo "Backing up current kubelet config..."
sudo cp "$KUBELET_CONFIG" "${KUBELET_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"

echo "Updating graceful shutdown settings..."
sudo sed -i 's/^shutdownGracePeriod: 0s$/shutdownGracePeriod: 2m0s/' "$KUBELET_CONFIG"
sudo sed -i 's/^shutdownGracePeriodCriticalPods: 0s$/shutdownGracePeriodCriticalPods: 30s/' "$KUBELET_CONFIG"

echo "Verifying configuration..."
if grep -q "shutdownGracePeriod: 2m0s" "$KUBELET_CONFIG" && \
   grep -q "shutdownGracePeriodCriticalPods: 30s" "$KUBELET_CONFIG"; then
    echo "✓ Configuration updated successfully"

    echo ""
    echo "Current graceful shutdown settings:"
    sudo grep -E "shutdownGracePeriod" "$KUBELET_CONFIG"

    echo ""
    echo "Restarting kubelet to apply changes..."
    sudo systemctl restart kubelet

    echo ""
    echo "Waiting for kubelet to become ready..."
    sleep 5

    if systemctl is-active --quiet kubelet; then
        echo "✓ Kubelet restarted successfully and is running"
    else
        echo "✗ WARNING: Kubelet failed to start!"
        echo "Check logs with: journalctl -u kubelet -n 50"
        exit 1
    fi
else
    echo "✗ Failed to update configuration"
    exit 1
fi
REMOTE_CONFIG

echo ""
echo "✓ Successfully configured graceful shutdown on $NODE"
echo ""
echo "Graceful shutdown settings:"
echo "  - Total shutdown time: 2 minutes"
echo "  - Critical pods (CNI, CSI, etc.): 30 seconds (reserved at end)"
echo "  - Regular pods: 90 seconds (2m - 30s)"
echo ""
echo "Kubelet will now automatically:"
echo "  - Detect systemd shutdown signals"
echo "  - Terminate regular pods first (90s grace period)"
echo "  - Terminate critical pods last (30s grace period)"
echo "  - Handle pod eviction and volume unmounting automatically"
