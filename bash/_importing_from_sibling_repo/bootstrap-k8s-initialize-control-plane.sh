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

# Configure kubeadm to use CRI-O instead of containerd
export CONTAINER_RUNTIME_ENDPOINT="unix:///var/run/crio/crio.sock"

# Setup VIP for HA control plane (before kubeadm init)
echo "Setting up VIP: $MASTER_PUBLIC_IP"
INTERFACE=$(ip route | grep default | awk '{print $5}')

# Manually assign the VIP for bootstrap
# This ensures the VIP is available immediately during kubeadm init
# FluxCD will deploy kube-vip DaemonSet later for proper HA management
sudo ip addr add $MASTER_PUBLIC_IP/32 dev $INTERFACE || true
echo "VIP $MASTER_PUBLIC_IP temporarily assigned to $INTERFACE for bootstrap"
echo "Note: FluxCD will deploy kube-vip DaemonSet for proper HA VIP management"

# Pull required images using CRI-O
sudo kubeadm config images pull --kubernetes-version="$KUBERNETES_VERSION" --cri-socket="unix:///var/run/crio/crio.sock"

# Initialize kubeadm with CRI-O
sudo kubeadm init \
  --cri-socket="unix:///var/run/crio/crio.sock" \
  --control-plane-endpoint="$MASTER_PUBLIC_IP" \
  --apiserver-cert-extra-sans="$MASTER_PUBLIC_IP" \
  --pod-network-cidr="$POD_CIDR" \
  --service-cidr="$SERVICE_CIDR" \
  --kubernetes-version="$KUBERNETES_VERSION" \
  --node-name "$NODENAME" \
  --ignore-preflight-errors=Swap \
  --upload-certs

# Configure kubectl for both root and the actual user
# Always configure for root since we're running with sudo
mkdir -p /root/.kube
sudo cp -f /etc/kubernetes/admin.conf /root/.kube/config

# Also configure for the actual user if running with sudo
if [ "$SUDO_USER" ]; then
    USER_HOME=$(eval echo ~$SUDO_USER)
    mkdir -p "$USER_HOME/.kube"
    sudo cp -f /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
    sudo chown "$SUDO_USER:$SUDO_USER" "$USER_HOME/.kube/config"
    echo "kubectl configured for user: $SUDO_USER"
fi

# Export KUBECONFIG for this script session (running as root)
export KUBECONFIG=/root/.kube/config

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
  --set bpf.masquerade=false \
  --set bgpControlPlane.enabled=true \
  --set loadBalancer.mode=dsr \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set enableIPv4Masquerade=false \
  --set bpf.lbExternalClusterIP=true

# Wait for Cilium to be ready
echo "Waiting for Cilium to be ready..."
# First wait for Cilium pods to be created
until kubectl get pods -n kube-system -l k8s-app=cilium 2>/dev/null | grep -q cilium; do
  echo "Waiting for Cilium pods to be created..."
  sleep 5
done
# Now wait for them to be ready
kubectl wait --for=condition=ready --timeout=300s -n kube-system pod -l k8s-app=cilium || true

# Also wait for Cilium operator
kubectl wait --for=condition=ready --timeout=300s -n kube-system pod -l name=cilium-operator || true

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