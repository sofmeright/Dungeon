#!/bin/bash
set -euxo pipefail
# Variables
NODENAME=$(hostname -s)
CILIUM_VERSION="1.18.2"          # Added quotes for consistency
KUBERNETES_VERSION="v1.34.1"     # v prefix is correct
POD_CIDR="192.168.144.0/20"
SERVICE_CIDR="10.144.0.0/12"
# Get PUBLIC IP (This is for subnet 172.22.144.0/24)
MASTER_PUBLIC_IP="172.22.144.105"
echo "Master IP: $MASTER_PUBLIC_IP"
echo "Kubernetes Version: $KUBERNETES_VERSION"
echo "Cilium Version: $CILIUM_VERSION"

# Pull required images
sudo kubeadm config images pull --kubernetes-version="$KUBERNETES_VERSION"

# Initialize kubeadm
sudo kubeadm init \
  --control-plane-endpoint="$MASTER_PUBLIC_IP" \
  --apiserver-cert-extra-sans="$MASTER_PUBLIC_IP" \
  --pod-network-cidr="$POD_CIDR" \
  --service-cidr="$SERVICE_CIDR" \
  --kubernetes-version="$KUBERNETES_VERSION" \
  --node-name "$NODENAME" \
  --ignore-preflight-errors=Swap \
  --upload-certs

mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

# Add Cilium Helm repo first
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium Network Plugin with production settings
helm install cilium cilium/cilium --version "$CILIUM_VERSION" \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set ipv4NativeRoutingCIDR="$POD_CIDR" \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="$MASTER_PUBLIC_IP" \
  --set k8sServicePort=6443 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set prometheus.enabled=true \
  --set operator.replicas=1 \
  --set bpf.masquerade=true \
  --set bgpControlPlane.enabled=true \
  --set loadBalancer.mode=snat

# Wait for Cilium to be ready
echo "Waiting for Cilium to be ready..."
kubectl wait --for=condition=ready --timeout=300s -n kube-system pod -l k8s-app=cilium

# Wait for nodes to be ready
kubectl wait --for=condition=Ready node --all --timeout=300s

echo "#!/bin/bash" > /tmp/kubeadm_join_cmd.sh
kubeadm token create --print-join-command >> /tmp/kubeadm_join_cmd.sh
chmod +x /tmp/kubeadm_join_cmd.sh

# Verify cluster health
echo "=== Cluster Status ==="
kubectl get nodes
echo ""
echo "=== System Pods ==="
kubectl get pods -A
echo ""
echo "=== Cilium Status ==="
kubectl -n kube-system exec ds/cilium -- cilium status --brief || true

echo ""
echo "Cluster initialized successfully!"
echo "Join command saved to: /tmp/kubeadm_join_cmd.sh"