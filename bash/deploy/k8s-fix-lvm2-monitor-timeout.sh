#!/bin/bash
################################################################################
# Fix lvm2-monitor Shutdown Timeout
#
# lvm2-monitor can hang during shutdown on Kubernetes nodes with Ceph RBD
# because it tries to monitor device-mapper devices that are already unmounted.
#
# This script adds a timeout override to prevent indefinite hangs.
#
# Usage:
#   ./k8s-fix-lvm2-monitor-timeout.sh <node-hostname>
################################################################################

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <node-hostname>"
    echo "Example: $0 dungeon-chest-001"
    exit 1
fi

NODE=$1

echo "Adding timeout override for lvm2-monitor on $NODE..."

ssh "$NODE" bash <<'REMOTE_CONFIG'
set -e

OVERRIDE_DIR="/etc/systemd/system/lvm2-monitor.service.d"
OVERRIDE_FILE="$OVERRIDE_DIR/timeout.conf"

echo "Creating systemd override directory..."
sudo mkdir -p "$OVERRIDE_DIR"

echo "Creating timeout override..."
sudo tee "$OVERRIDE_FILE" > /dev/null <<'EOF'
[Service]
# Add timeout to prevent indefinite hangs during shutdown
# lvm2-monitor can hang when Ceph RBD device-mapper devices are already gone
TimeoutStopSec=30
EOF

echo "Verifying override..."
cat "$OVERRIDE_FILE"

echo ""
echo "Reloading systemd..."
sudo systemctl daemon-reload

echo ""
echo "Checking lvm2-monitor service configuration..."
systemctl show lvm2-monitor.service --property=TimeoutStopUSec

echo ""
echo "✓ lvm2-monitor timeout override created"
REMOTE_CONFIG

echo ""
echo "✓ Successfully configured lvm2-monitor timeout on $NODE"
echo ""
echo "Configuration applied:"
echo "  - TimeoutStopSec: 30 seconds"
echo "  - lvm2-monitor will be killed after 30s if it hangs during shutdown"
echo ""
echo "This should prevent the node from hanging indefinitely during reboot"
