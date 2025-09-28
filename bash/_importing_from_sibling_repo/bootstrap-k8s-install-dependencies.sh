#!/bin/bash
set -euxo pipefail

# Kubernetes Variables
KUBERNETES_VERSION="v1.34"
CRIO_VERSION="v1.34"

# Disable swap permanently
sudo swapoff -a
# Remove swap from /etc/fstab
sudo sed -i '/ swap / s/^/#/' /etc/fstab
# Remove any swap files that may exist
sudo rm -f /swap.img /swapfile

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl params required by setup
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# Install prerequisites
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common jq

# Install CRI-O Runtime (using new repository location)
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
    sudo gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" |
    sudo tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update -y
sudo apt-get install -y cri-o

# Install required CRI-O dependencies
# DO NOT install crun - CRI-O comes with its own bundled compatible version
sudo apt-get install -y conmon containernetworking-plugins

# Create containers policy.json (required for pulling images)
sudo mkdir -p /etc/containers
cat <<EOF | sudo tee /etc/containers/policy.json
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ],
    "transports": {
        "docker": {
            "registry.k8s.io": [
                {
                    "type": "insecureAcceptAnything"
                }
            ],
            "docker.io": [
                {
                    "type": "insecureAcceptAnything"
                }
            ]
        }
    }
}
EOF

# Create temporary CNI configuration for CRI-O to start
# This will be replaced by Cilium when the control plane is initialized
sudo mkdir -p /etc/cni/net.d
cat <<EOF | sudo tee /etc/cni/net.d/10-crio-bridge.conf
{
    "cniVersion": "1.0.0",
    "name": "crio",
    "type": "bridge",
    "bridge": "cni0",
    "isGateway": true,
    "ipMasq": true,
    "hairpinMode": true,
    "ipam": {
        "type": "host-local",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ],
        "ranges": [
            [{ "subnet": "192.168.144.0/20" }]
        ]
    }
}
EOF

# Configure CRI-O to use its bundled crun runtime
sudo mkdir -p /etc/crio/crio.conf.d/
cat <<EOF | sudo tee /etc/crio/crio.conf.d/10-runtime.conf
[crio.runtime]
default_runtime = "crun"

[crio.runtime.runtimes.crun]
runtime_path = "/usr/libexec/crio/crun"
runtime_type = "oci"
EOF

sudo systemctl daemon-reload
sudo systemctl enable crio --now
echo "CRI-O runtime installed successfully"

# Install Kubernetes components
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key |
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" |
    sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl

# Prevent automatic updates
sudo apt-mark hold kubelet kubeadm kubectl cri-o

# Get the local IP (first non-loopback IP)
local_ip=$(hostname -I | awk '{print $1}')
echo "Local IP: $local_ip"

# Configure kubelet with local IP
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF

# Restart kubelet to apply configuration
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Install Helm (needed for Cilium installation)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Pre-pull some images to speed up cluster init (optional)
sudo crictl pull registry.k8s.io/pause:3.10

echo "==================================="
echo "K8's dependency installation completed!"
echo "Node IP: $local_ip"
echo "CRI-O Version: $(crio --version | head -1)"
echo "Kubelet Version: $(kubelet --version)"
echo "Kubeadm Version: $(kubeadm version -o short)"
echo "==================================="