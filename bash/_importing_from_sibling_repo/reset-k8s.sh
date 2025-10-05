#!/bin/bash
set -x

echo "=== FULL K8S RESET - CLEANING EVERYTHING ==="

# Reset kubeadm if it was initialized
sudo kubeadm reset -f --cri-socket=unix:///var/run/crio/crio.sock 2>/dev/null || true

# Stop all services
sudo systemctl stop kubelet || true
sudo systemctl stop crio || true

# Clean up CRI-O containers and images
sudo crictl rm -af 2>/dev/null || true
sudo crictl rmp -af 2>/dev/null || true

# Remove all CRI-O state
sudo rm -rf /var/lib/crio/*
sudo rm -rf /run/crio/*
sudo rm -rf /var/log/crio/*

# Remove all Kubernetes state
sudo rm -rf /etc/kubernetes/
sudo rm -rf /var/lib/kubelet/
sudo rm -rf /var/lib/etcd/
sudo rm -rf ~/.kube/

# Remove CNI configs
sudo rm -rf /etc/cni/net.d/*

# Remove CRI-O configs we added
sudo rm -rf /etc/crio/crio.conf.d/*

# Clean iptables rules
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

# Remove network interfaces created by CNI
sudo ip link delete cni0 2>/dev/null || true
sudo ip link delete flannel.1 2>/dev/null || true

echo "=== SYSTEM CLEANED ==="
echo "Now run: sudo bash bash/_importing_from_sibling_repo/bootstrap-k8s-install-dependencies.sh"
echo "Then run: sudo bash bash/_importing_from_sibling_repo/bootstrap-k8s-initialize-control-plane.sh"