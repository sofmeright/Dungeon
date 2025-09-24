#!/bin/bash
set -euxo pipefail

# Kubernetes Variables - Matching versions
KUBERNETES_VERSION="v1.34"     # Use v1.34 for apt repos (not v1.34.1)
CRIO_VERSION="1.34"            # CRI-O version without 'v' prefix
OS="xUbuntu_24.04"            # Ubuntu 24.04 for OpenSUSE repos

# Disable swap
sudo swapoff -a
# Remove swap from /etc/fstab
sudo sed -i '/ swap / s/^/#/' /etc/fstab

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

# Install CRI-O Runtime v1.34
# Using the OpenSUSE Build Service repository which has v1.34
curl -fsSL "https://download.opensuse.org/repositories/isv:/kubernetes:/addons:/cri-o:/stable:/v${CRIO_VERSION}/${OS}/Release.key" |
    sudo gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/kubernetes:/addons:/cri-o:/stable:/v${CRIO_VERSION}/${OS}/ /" |
    sudo tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update -y
sudo apt-get install -y cri-o

# Configure CRI-O for the correct CNI
sudo mkdir -p /etc/crio/crio.conf.d/
cat <<EOF | sudo tee /etc/crio/crio.conf.d/10-crun.conf
[crio.runtime]
default_runtime = "crun"
[crio.runtime.runtimes.crun]
runtime_path = "/usr/bin/crun"
EOF

sudo systemctl daemon-reload
sudo systemctl enable crio --now
echo "CRI-O runtime installed successfully"

# Install Kubernetes components
K8S_REPO_URL="https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VERSION}/deb/"
curl -fsSL "${K8S_REPO_URL}Release.key" |
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${K8S_REPO_URL} /" |
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