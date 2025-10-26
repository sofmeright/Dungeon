#!/bin/bash
################################################################################
# Install k8s-graceful-shutdown.sh on a worker node
#
# This script installs the graceful shutdown orchestrator and systemd service
# on a single worker node.
#
# Usage:
#   ./install-graceful-shutdown.sh <node-hostname>
################################################################################

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <node-hostname>"
    echo "Example: $0 dungeon-chest-001"
    exit 1
fi

NODE=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing graceful shutdown service on $NODE..."

# Copy script to node
scp "$SCRIPT_DIR/k8s-boot-mgmt-shutdown.sh" "$NODE:/tmp/k8s-graceful-shutdown.sh"

# Install on remote node
ssh "$NODE" bash <<'REMOTE_INSTALL'
set -e

# Move script to /usr/local/bin
sudo mv /tmp/k8s-graceful-shutdown.sh /usr/local/bin/k8s-graceful-shutdown.sh
sudo chmod +x /usr/local/bin/k8s-graceful-shutdown.sh

# Create systemd service
sudo tee /etc/systemd/system/k8s-graceful-shutdown.service > /dev/null <<'EOF'
[Unit]
Description=Kubernetes Graceful Node Shutdown Orchestrator
Documentation=https://github.com/sofmeright/Dungeon
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target
Before=kubelet.service containerd.service crio.service
Before=lvm2-monitor.service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/true
ExecStop=/usr/local/bin/k8s-graceful-shutdown.sh
TimeoutStopSec=180
RemainAfterExit=yes
KillMode=process

# Resource limits to prevent hanging
MemoryMax=256M
TasksMax=100

# Logging
StandardOutput=journal+console
StandardError=journal+console
SyslogIdentifier=k8s-shutdown

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable k8s-graceful-shutdown.service

# Create log file with proper permissions
sudo touch /var/log/k8s-shutdown.log
sudo chmod 644 /var/log/k8s-shutdown.log

echo "✓ Graceful shutdown service installed and enabled"
REMOTE_INSTALL

echo "✓ Successfully installed graceful shutdown service on $NODE"
echo ""
echo "To test the service:"
echo "  ssh $NODE sudo systemctl start k8s-graceful-shutdown.service"
echo ""
echo "To view logs:"
echo "  ssh $NODE tail -f /var/log/k8s-shutdown.log"
