#!/bin/bash
# GPU Node Setup Script
# Configures CRI-O to work with nvidia-container-runtime
# Run this on nodes that have GPUs and need nvidia-container-runtime

set -e

echo "=== GPU Node Setup ==="

# Install runc if not present
if ! command -v runc &> /dev/null; then
    echo "Installing runc..."
    sudo apt update
    sudo apt install -y runc
else
    echo "runc already installed at $(which runc)"
fi

# Create symlink to ensure runc is in PATH for nvidia-container-runtime
echo "Creating runc symlink in /usr/local/bin..."
sudo ln -sf /usr/bin/runc /usr/local/bin/runc

# Verify runc is accessible
if command -v runc &> /dev/null; then
    echo "✓ runc is available: $(which runc)"
    runc --version
else
    echo "✗ ERROR: runc still not found in PATH"
    exit 1
fi

# Fix nvidia-container-runtime script to use absolute path to runc
# The script has "exec runc" which fails because runc is not in PATH when CRI-O calls it
# We need to change it to "exec /usr/bin/runc" for absolute path
# Also redirect echo to stderr so CRI-O doesn't try to parse it as JSON
if [ -f /usr/local/nvidia/toolkit/nvidia-container-runtime ]; then
    echo "Fixing nvidia-container-runtime script..."
    sudo sed -i 's|exec runc |exec /usr/bin/runc |g' /usr/local/nvidia/toolkit/nvidia-container-runtime
    sudo sed -i 's|echo "nvidia driver modules|echo "nvidia driver modules|g' /usr/local/nvidia/toolkit/nvidia-container-runtime
    sudo sed -i 's|invoking runc directly"|invoking runc directly" >\&2|g' /usr/local/nvidia/toolkit/nvidia-container-runtime
    echo "✓ nvidia-container-runtime script updated"
    echo "Script content (first 10 lines):"
    head -10 /usr/local/nvidia/toolkit/nvidia-container-runtime
else
    echo "⚠ WARNING: /usr/local/nvidia/toolkit/nvidia-container-runtime not found"
    echo "This script should be run on nodes with nvidia-container-runtime installed"
fi

# Restart CRI-O to pick up changes
echo "Restarting CRI-O service..."
sudo systemctl restart crio

# Wait for CRI-O to be ready
sleep 5

# Verify CRI-O is running
if sudo systemctl is-active --quiet crio; then
    echo "✓ CRI-O is running"
else
    echo "✗ ERROR: CRI-O failed to start"
    sudo systemctl status crio
    exit 1
fi

echo ""
echo "=== GPU Node Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Delete any failed Cilium pods on this node:"
echo "   kubectl delete pod -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=$(hostname)"
echo ""
echo "2. Verify Cilium starts successfully:"
echo "   kubectl get pods -n kube-system -l k8s-app=cilium -o wide | grep $(hostname)"
