#!/bin/bash
set -e

echo "==================================="
echo "Kubernetes Cluster Networking Fix"
echo "==================================="
echo ""

# 1. Disable swap permanently
echo "Step 1: Disabling swap permanently..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
# Remove any swap files that may exist
sudo rm -f /swap.img /swapfile
echo "✓ Swap disabled permanently"

# 2. Delete kube-proxy if it exists
echo ""
echo "Step 2: Removing kube-proxy..."
kubectl delete ds -n kube-system kube-proxy 2>/dev/null || echo "  kube-proxy DaemonSet not found (already deleted)"
kubectl delete cm -n kube-system kube-proxy 2>/dev/null || echo "  kube-proxy ConfigMap not found (already deleted)"
echo "✓ kube-proxy removed"

# 3. Complete iptables cleanup
echo ""
echo "Step 3: Cleaning ALL kube-proxy iptables rules..."

# Clean specific chains first
sudo iptables -t nat -F KUBE-SERVICES 2>/dev/null || true
sudo iptables -t nat -F KUBE-POSTROUTING 2>/dev/null || true
sudo iptables -t nat -F KUBE-NODEPORTS 2>/dev/null || true
sudo iptables -t filter -F KUBE-FORWARD 2>/dev/null || true
sudo iptables -t filter -F KUBE-SERVICES 2>/dev/null || true

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

# 4. Restart kubelet
echo ""
echo "Step 4: Restarting kubelet..."
sudo systemctl restart kubelet
sleep 5
sudo systemctl status kubelet --no-pager | head -5
echo "✓ kubelet restarted"

# 5. Restart Cilium
echo ""
echo "Step 5: Restarting Cilium DaemonSet..."
kubectl rollout restart -n kube-system ds/cilium
kubectl rollout status -n kube-system ds/cilium --timeout=120s
echo "✓ Cilium restarted"

# 6. Restart Cilium operator
echo ""
echo "Step 6: Restarting Cilium Operator..."
kubectl rollout restart -n kube-system deployment/cilium-operator
sleep 10
echo "✓ Cilium operator restarted"

# 7. Verify cleanup
echo ""
echo "Step 7: Verification..."
echo -n "  Checking for remaining KUBE iptables rules: "
remaining=$(sudo iptables-save | grep -c KUBE || echo "0")
if [ "$remaining" -eq "0" ]; then
    echo "CLEAN ✓"
else
    echo "WARNING: $remaining KUBE rules still found"
    echo "  Showing first 5:"
    sudo iptables-save | grep KUBE | head -5
fi

echo ""
echo "Step 8: Checking Cilium status..."
kubectl -n kube-system exec ds/cilium -- cilium status --brief || true

echo ""
echo "==================================="
echo "Fix script completed!"
echo ""
echo "Now checking cluster health..."
echo ""

# Show current status
kubectl get nodes
echo ""
echo "Pods in error state:"
kubectl get pods -A | grep -v Running | grep -v Completed | grep -v NAMESPACE | wc -l

echo ""
echo "To run this on other nodes:"
echo "  1. Copy this script to each node"
echo "  2. Run: bash /tmp/fix-cluster-networking.sh"
echo ""
echo "Note: The iptables cleanup and kubelet restart need to run on EACH node"
echo "==================================="