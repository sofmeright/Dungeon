#!/bin/bash
################################################################################
# Fix systemd-logind InhibitDelayMaxSec for Kubelet Graceful Shutdown
#
# systemd-logind limits how long processes can delay shutdown via InhibitDelayMaxSec.
# Kubelet needs at least as much time as shutdownGracePeriod to perform graceful shutdown.
#
# This script increases InhibitDelayMaxSec to match kubelet's requirements.
#
# Usage:
#   ./k8s-fix-logind-inhibit-delay.sh <node-hostname>
################################################################################

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <node-hostname>"
    echo "Example: $0 dungeon-chest-001"
    exit 1
fi

NODE=$1

echo "Fixing systemd-logind InhibitDelayMaxSec on $NODE..."

# Configure logind on remote node
ssh "$NODE" bash <<'REMOTE_CONFIG'
set -e

LOGIND_CONF="/etc/systemd/logind.conf"
LOGIND_OVERRIDE_DIR="/etc/systemd/logind.conf.d"
LOGIND_OVERRIDE="$LOGIND_OVERRIDE_DIR/kubelet-inhibit-delay.conf"

echo "Creating logind configuration override..."
sudo mkdir -p "$LOGIND_OVERRIDE_DIR"

sudo tee "$LOGIND_OVERRIDE" > /dev/null <<'EOF'
# Increase InhibitDelayMaxSec for Kubelet graceful shutdown
# Kubelet needs shutdownGracePeriod (2m) + buffer time
[Login]
InhibitDelayMaxSec=180
EOF

echo "Verifying configuration..."
cat "$LOGIND_OVERRIDE"

echo ""
echo "Restarting systemd-logind to apply changes..."
sudo systemctl restart systemd-logind

echo ""
echo "Checking new InhibitDelayMaxSec value..."
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager InhibitDelayMaxUSec || echo "(busctl not available, configuration will be applied on next boot)"

echo ""
echo "Restarting kubelet to pick up new logind settings..."
sudo systemctl restart kubelet

echo ""
echo "Waiting for kubelet to become ready..."
sleep 5

if systemctl is-active --quiet kubelet; then
    echo "✓ Kubelet restarted successfully"

    echo ""
    echo "Checking if graceful shutdown manager started successfully..."
    sudo journalctl -u kubelet --since "30 seconds ago" | grep -i "shutdown manager" || echo "No shutdown manager logs yet (check after next kubelet restart)"
else
    echo "✗ WARNING: Kubelet failed to start!"
    echo "Check logs with: journalctl -u kubelet -n 50"
    exit 1
fi
REMOTE_CONFIG

echo ""
echo "✓ Successfully configured systemd-logind on $NODE"
echo ""
echo "Configuration applied:"
echo "  - InhibitDelayMaxSec: 180 seconds (3 minutes)"
echo "  - This allows kubelet's 2-minute graceful shutdown + 1-minute buffer"
echo ""
echo "Kubelet graceful shutdown should now work properly during reboot/shutdown"
