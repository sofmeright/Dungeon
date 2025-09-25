#!/bin/bash
set -euxo pipefail

# This script is for joining additional control plane nodes to an existing cluster
# Run bootstrap-k8s-install-dependencies.sh first on the new node
# NOTE: kube-vip will be automatically deployed by FluxCD as a DaemonSet

VIP="172.22.144.105"

echo "============================================"
echo "Control Plane Join Helper"
echo "============================================"
echo ""
echo "This node will join as a control plane node."
echo "kube-vip will be automatically configured via FluxCD DaemonSet"
echo ""
echo "To join this node, run these commands on the FIRST master:"
echo ""
echo "1. Upload certificates:"
echo "   sudo kubeadm init phase upload-certs --upload-certs"
echo ""
echo "2. Generate join command:"
echo "   sudo kubeadm token create --print-join-command"
echo ""
echo "3. Run the join command on THIS node with added flags:"
echo "   <join-command> --control-plane --certificate-key <key-from-step-1> --cri-socket=unix:///var/run/crio/crio.sock"
echo ""
echo "Example:"
echo "   sudo kubeadm join $VIP:6443 --token abc123 \\"
echo "     --discovery-token-ca-cert-hash sha256:xyz789 \\"
echo "     --control-plane \\"
echo "     --certificate-key def456 \\"
echo "     --cri-socket=unix:///var/run/crio/crio.sock"
echo ""
echo "============================================"