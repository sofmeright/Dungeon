#!/bin/bash
set -e

echo "==================================="
echo "Kubernetes Cluster Networking Fix"
echo "==================================="
echo ""

# 1. Disable swap
echo "Step 1: Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
echo "✓ Swap disabled"

# 2. Complete iptables cleanup (runs on all nodes)
echo ""
echo "Step 2: Cleaning ALL kube-proxy iptables rules..."

# Clean specific chains first
sudo iptables -t nat -F KUBE-SERVICES 2>/dev/null || true
sudo iptables -t nat -F KUBE-POSTROUTING 2>/dev/null || true
sudo iptables -t nat -F KUBE-NODEPORTS 2>/dev/null || true
sudo iptables -t filter -F KUBE-FORWARD 2>/dev/null || true
sudo iptables -t filter -F KUBE-SERVICES 2>/dev/null || true
sudo iptables -t filter -F KUBE-EXTERNAL-SERVICES 2>/dev/null || true
sudo iptables -t filter -F KUBE-PROXY-FIREWALL 2>/dev/null || true

# Remove all KUBE-* rules from all tables
for table in nat filter mangle raw; do
    echo "  Cleaning $table table..."

    # Remove references to KUBE- chains from built-in chains
    sudo iptables -t $table -S 2>/dev/null | grep -E "KUBE-|KUBE-PROXY" | grep -E "^-A (INPUT|OUTPUT|FORWARD|PREROUTING|POSTROUTING)" | while read rule; do
        delete_rule=$(echo "$rule" | sed 's/^-A /-D /')
        sudo iptables -t $table $delete_rule 2>/dev/null || true
    done

    # Flush and delete all KUBE- chains
    sudo iptables -t $table -L -n 2>/dev/null | grep "^Chain KUBE" | awk '{print $2}' | while read chain; do
        sudo iptables -t $table -F $chain 2>/dev/null || true
        sudo iptables -t $table -X $chain 2>/dev/null || true
    done
done

echo "✓ iptables rules cleaned"

# 3. Kill any remaining kube-proxy processes
echo ""
echo "Step 3: Killing any kube-proxy processes..."
sudo pkill -f kube-proxy || true
echo "✓ kube-proxy processes killed"

# 4. Restart kubelet
echo ""
echo "Step 4: Restarting kubelet..."
sudo systemctl restart kubelet
sleep 5
sudo systemctl status kubelet --no-pager | head -5
echo "✓ kubelet restarted"

# 5. Verify cleanup
echo ""
echo "Step 5: Verification..."
echo -n "  Checking for remaining KUBE iptables rules: "
remaining=$(sudo iptables-save | grep -c KUBE || echo "0")
if [ "$remaining" -eq "0" ]; then
    echo "CLEAN ✓"
else
    echo "WARNING: $remaining KUBE rules still found"
    echo "  Note: Some KUBE-IPTABLES-HINT and KUBE-KUBELET-CANARY rules may persist (these are OK)"
fi

# 6. Check if this is a control-plane node
echo ""
echo "Step 6: Checking node role..."
if [ -f /etc/kubernetes/admin.conf ]; then
    echo "  This is a control-plane node"

    # Set kubeconfig for kubectl commands
    export KUBECONFIG=/etc/kubernetes/admin.conf

    # Only run kubectl commands on control plane nodes
    echo ""
    echo "Step 7: Kubernetes operations (control-plane only)..."

    # Delete kube-proxy if exists (only needs to run once)
    kubectl delete ds -n kube-system kube-proxy 2>/dev/null || echo "  kube-proxy DaemonSet not found (OK)"
    kubectl delete cm -n kube-system kube-proxy 2>/dev/null || echo "  kube-proxy ConfigMap not found (OK)"

    # Restart Cilium (only needs to run once from any control plane)
    echo "  Restarting Cilium DaemonSet..."
    kubectl rollout restart -n kube-system ds/cilium 2>/dev/null || echo "  Could not restart Cilium (may need to run from different node)"

    # Show status
    echo ""
    echo "Cluster status:"
    kubectl get nodes 2>/dev/null || echo "  Could not get nodes"
else
    echo "  This is a worker node (skipping kubectl operations)"
fi

echo ""
echo "==================================="
echo "Fix completed on node: $(hostname)"
echo "==================================="
echo ""
echo "IMPORTANT: This script must be run on ALL nodes!"
echo "The iptables cleanup and kubelet restart are per-node operations."
echo ""
echo "To check if the fix worked:"
echo "  1. All nodes should show 'Ready'"
echo "  2. Pods should stop crashing"
echo "  3. From a control-plane node: kubectl get pods -A | grep -v Running"
echo "==================================="