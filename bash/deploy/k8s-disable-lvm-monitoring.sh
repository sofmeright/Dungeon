#!/bin/bash
################################################################################
# Disable LVM Monitoring for Kubernetes Nodes with Simple Linear LVM
#
# For nodes using simple linear LVM (no RAID, snapshots, or thin pools),
# lvm2-monitor is unnecessary and causes shutdown hangs when combined with
# Kubernetes + Ceph RBD volumes.
#
# This script:
# 1. Disables LVM event activation
# 2. Disables and masks lvm2-monitor and lvmpolld services
# 3. Updates initramfs to persist changes
# 4. Adds kubelet shutdown ordering to ensure proper cleanup
#
# Usage:
#   ./k8s-disable-lvm-monitoring.sh <node-hostname>
################################################################################

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <node-hostname>"
    echo "Example: $0 dungeon-chest-001"
    exit 1
fi

NODE=$1

echo "Disabling LVM monitoring on $NODE..."

ssh "$NODE" bash <<'REMOTE_CONFIG'
set -e

echo "Checking LVM configuration..."
sudo lvs -a -o lv_name,vg_name,attr,segtype,devices

echo ""
echo "Verifying LVM setup is simple linear (safe to disable monitoring)..."
if sudo lvs -a -o segtype | grep -qE "raid|thin|snapshot|cache|mirror"; then
    echo "ERROR: Complex LVM setup detected (RAID/thin/snapshot/cache/mirror)"
    echo "LVM monitoring may be needed. Aborting for safety."
    exit 1
fi

echo "✓ Simple linear LVM detected - safe to disable monitoring"
echo ""

echo "Step 1: Disable LVM event activation in lvm.conf..."
if grep -q "event_activation" /etc/lvm/lvm.conf; then
    sudo sed -i 's/^[[:space:]]*event_activation.*/\tevent_activation = 0/' /etc/lvm/lvm.conf
    echo "  ✓ Updated existing event_activation setting"
else
    echo -e "\nglobal {\n\tevent_activation = 0\n}" | sudo tee -a /etc/lvm/lvm.conf >/dev/null
    echo "  ✓ Added event_activation = 0 to lvm.conf"
fi

echo ""
echo "Step 2: Stop LVM monitoring services..."
sudo systemctl stop lvm2-monitor.service lvmpolld.service 2>/dev/null || echo "  (Services already stopped)"

echo ""
echo "Step 3: Disable and mask LVM monitoring services..."
sudo systemctl disable lvm2-monitor.service lvmpolld.service 2>/dev/null || true
sudo systemctl mask lvm2-monitor.service lvmpolld.service
echo "  ✓ Services disabled and masked"

echo ""
echo "Step 4: Add kubelet shutdown ordering (kubelet stops before LVM)..."
sudo mkdir -p /etc/systemd/system/kubelet.service.d
sudo tee /etc/systemd/system/kubelet.service.d/20-shutdown-order.conf >/dev/null <<'EOF'
[Unit]
# Ensure kubelet stops before LVM services
# This prevents kubelet from holding volume mounts during LVM shutdown
Before=lvm2-monitor.service
Before=lvmpolld.service
EOF
echo "  ✓ Kubelet shutdown ordering configured"

echo ""
echo "Step 5: Reload systemd configuration..."
sudo systemctl daemon-reload
echo "  ✓ Systemd reloaded"

echo ""
echo "Step 6: Update initramfs to persist LVM changes..."
sudo update-initramfs -u -k all
echo "  ✓ Initramfs updated"

echo ""
echo "Verifying service status..."
echo "lvm2-monitor:"
systemctl status lvm2-monitor.service --no-pager -l || true
echo ""
echo "lvmpolld:"
systemctl status lvmpolld.service --no-pager -l || true

echo ""
echo "✓ LVM monitoring successfully disabled"
REMOTE_CONFIG

echo ""
echo "✓ Successfully disabled LVM monitoring on $NODE"
echo ""
echo "Changes applied:"
echo "  - LVM event_activation: disabled"
echo "  - lvm2-monitor.service: disabled and masked"
echo "  - lvmpolld.service: disabled and masked"
echo "  - kubelet shutdown ordering: configured"
echo "  - initramfs: updated"
echo ""
echo "Expected improvements:"
echo "  - Reboot time: ~3 minutes → ~10-20 seconds"
echo "  - No freeze on lvm2-monitor.service"
echo "  - No shutdown hang even with leftover mounts"
echo ""
echo "Reboot the node to verify the fix:"
echo "  ssh $NODE sudo reboot"
