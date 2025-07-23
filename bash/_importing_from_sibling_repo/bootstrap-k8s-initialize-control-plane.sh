#!/bin/bash
set -euxo pipefail
# Variables
NODENAME=$(hostname -s)
POD_CIDR="192.168.22.0/16"
SERVICE_CIDR="10.0.22.0/12"
# Get PUBLIC IP
MASTER_PUBLIC_IP=172.22.22.105
echo "Master IP: $MASTER_PUBLIC_IP"
# Pull required images
sudo kubeadm config images pull
# Initialize kubeadm
sudo kubeadm init \
  --control-plane-endpoint="$MASTER_PUBLIC_IP" \
  --apiserver-cert-extra-sans="$MASTER_PUBLIC_IP" \
  --pod-network-cidr=192.168.22.0/16 \
  --service-cidr=10.0.22.0/12 \
  --kubernetes-version=v1.31.0 \
  --node-name "$NODENAME" \
  --ignore-preflight-errors=Swap \
  --upload-certs
mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" /etc/kubernetes/admin.conf
# Install Calico Network Plugin
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml
# Wait for api-server to be up
until kubectl get nodes; do
  echo "Waiting for API server to be available..."
  sleep 5
done
echo "#!/bin/bash" > /tmp/kubeadm_join_cmd.sh
kubeadm token create --print-join-command >> /tmp/kubeadm_join_cmd.sh
chmod +x /tmp/kubeadm_join_cmd.sh
