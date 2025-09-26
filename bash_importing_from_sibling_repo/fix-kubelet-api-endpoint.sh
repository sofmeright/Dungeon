#!/bin/bash
set -e

echo "==================================="
echo "Fix Kubelet API Endpoint Configuration"
echo "==================================="
echo ""

VIP="172.22.144.105"
CURRENT_NODE=$(hostname)

echo "Current node: $CURRENT_NODE"
echo ""

# Check current configuration
echo "Step 1: Checking current kubelet configuration..."
if [ -f /etc/kubernetes/kubelet.conf ]; then
    CURRENT_SERVER=$(sudo grep "server:" /etc/kubernetes/kubelet.conf | awk '{print $2}')
    echo "  Current API server: $CURRENT_SERVER"

    if [[ "$CURRENT_SERVER" == "https://$VIP:6443" ]]; then
        echo "  ✓ Already pointing to VIP, no change needed"
    else
        echo "  ✗ NOT pointing to VIP, needs fixing!"

        echo ""
        echo "Step 2: Backing up kubelet.conf..."
        sudo cp /etc/kubernetes/kubelet.conf /etc/kubernetes/kubelet.conf.backup.$(date +%Y%m%d-%H%M%S)
        echo "  ✓ Backup created"

        echo ""
        echo "Step 3: Updating API server endpoint to VIP..."
        sudo sed -i "s|server:.*|server: https://$VIP:6443|" /etc/kubernetes/kubelet.conf
        echo "  ✓ Updated to: https://$VIP:6443"
    fi
else
    echo "  Warning: /etc/kubernetes/kubelet.conf not found (might be a different path on this node)"
fi

# Also check bootstrap-kubelet.conf if it exists
if [ -f /etc/kubernetes/bootstrap-kubelet.conf ]; then
    echo ""
    echo "Step 4: Checking bootstrap-kubelet.conf..."
    CURRENT_BOOTSTRAP=$(sudo grep "server:" /etc/kubernetes/bootstrap-kubelet.conf 2>/dev/null | awk '{print $2}')
    if [ ! -z "$CURRENT_BOOTSTRAP" ]; then
        echo "  Current bootstrap server: $CURRENT_BOOTSTRAP"
        sudo sed -i "s|server:.*|server: https://$VIP:6443|" /etc/kubernetes/bootstrap-kubelet.conf
        echo "  ✓ Updated bootstrap config"
    fi
fi

# Check admin.conf on control plane nodes
if [ -f /etc/kubernetes/admin.conf ]; then
    echo ""
    echo "Step 5: Checking admin.conf (control plane)..."
    CURRENT_ADMIN=$(sudo grep "server:" /etc/kubernetes/admin.conf | awk '{print $2}')
    echo "  Current admin server: $CURRENT_ADMIN"
    if [[ "$CURRENT_ADMIN" != "https://$VIP:6443" ]]; then
        sudo cp /etc/kubernetes/admin.conf /etc/kubernetes/admin.conf.backup.$(date +%Y%m%d-%H%M%S)
        sudo sed -i "s|server:.*|server: https://$VIP:6443|" /etc/kubernetes/admin.conf
        echo "  ✓ Updated admin.conf to VIP"

        # Update local kubeconfig if exists
        if [ -f ~/.kube/config ]; then
            cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d-%H%M%S)
            sed -i "s|server:.*|server: https://$VIP:6443|" ~/.kube/config
            echo "  ✓ Updated local kubeconfig"
        fi
    fi
fi

# Update kubeadm config if exists
if [ -f /etc/kubernetes/kubeadm-flags.env ]; then
    echo ""
    echo "Step 6: Checking kubeadm flags..."
    if ! grep -q "cri-socket" /etc/kubernetes/kubeadm-flags.env; then
        echo "  Adding CRI-O socket to kubeadm flags..."
        sudo sed -i 's/KUBELET_KUBEADM_ARGS="/KUBELET_KUBEADM_ARGS="--cri-socket=unix:\/\/\/var\/run\/crio\/crio.sock /' /etc/kubernetes/kubeadm-flags.env
        echo "  ✓ Added CRI-O socket"
    else
        echo "  ✓ CRI-O socket already configured"
    fi
fi

echo ""
echo "Step 7: Restarting kubelet..."
sudo systemctl restart kubelet
sleep 5
sudo systemctl status kubelet --no-pager | head -5
echo "✓ Kubelet restarted"

echo ""
echo "==================================="
echo "Fix completed on node: $CURRENT_NODE"
echo "==================================="
echo ""
echo "Verification:"
sudo grep "server:" /etc/kubernetes/kubelet.conf
echo ""
echo "This script should be run on ALL nodes!"
echo "==================================="