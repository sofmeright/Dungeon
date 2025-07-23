#!/bin/bash

# deploy-lxc_container-ubuntu_24.04.sh %LXC_ID% %LXE_NAME% %STORAGE% %CI_USER% %CI_PASSWORD% %SSH_PUBKEY%

# VM and storage identifiers
LXE_ID=$1
STORAGE=Seed_Bank

# Define the VM name and Ubuntu image parameters
LXE_NAME=$2
STORAGE=$3  # Adjust if using a different storage backend
IMAGE_URL="https://cloud-images.ubuntu.com/daily/server/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
IMAGE_PATH="/var/lib/vz/template/iso/$(basename ${IMAGE_URL})"

# Cloud‑Init credentials (consider stronger hashing for production)
CI_USER=$4
CI_PASSWORD=$5

# Create an SSH public key file for injecting into the VM
echo $6 > ssh.pub

# 1. Download the Ubuntu 24.04 Cloud Image if not already present
if [ ! -f "${IMAGE_PATH}" ]; then
  echo "Downloading Ubuntu 24.04 Cloud Image..."
  wget -P /var/lib/vz/template/iso/ "${IMAGE_URL}"
else
  echo "Image already exists at ${IMAGE_PATH}"
fi

set -x  # Enable command echoing for debugging

# Destroy any existing VM with the same LXE_ID to avoid conflicts
qm destroy $LXE_ID 2>/dev/null || true

# Create a new VM with UEFI support and custom hardware configurations
echo "Creating VM ${LXE_NAME} with LXE_ID ${LXE_ID}..."
qm create ${LXE_ID} \
  --name "${LXE_NAME}" \
  --ostype l26 \
  --memory 2048 \
  --cores 2 \
  --agent 1 \
  --bios ovmf --machine q35 --efidisk0 ${STORAGE}:0,pre-enrolled-keys=0 \
  --cpu host --socket 1 --cores 2 \
  --vga serial0 --serial0 socket \
  --net0 virtio,bridge=vmbr0

# Import the downloaded disk image into Proxmox storage
echo "Importing disk image..."
qm importdisk ${LXE_ID} "${IMAGE_PATH}" ${STORAGE}

# Attach the imported disk as a VirtIO disk using the SCSI controller
qm set $LXE_ID --scsihw virtio-scsi-pci --virtio0 $STORAGE:vm-${LXE_ID}-disk-1,discard=on

# Resize the disk by adding an additional 8G
qm resize ${LXE_ID} virtio0 +8G

# Configure the VM to boot from the VirtIO disk
qm set $LXE_ID --boot order=virtio0

# Attach a Cloud‑Init drive (recommended on UEFI systems using SCSI)
qm set $LXE_ID --scsi1 $STORAGE:cloudinit

# Create a custom Cloud‑Init configuration snippet
cat << EOF | tee /var/lib/vz/snippets/ubuntu.yaml
#cloud-config
runcmd:
    - apt-get update
    - apt-get install -y qemu-guest-agent htop
    - systemctl enable ssh
    - reboot
EOF

# Apply Cloud‑Init customizations and additional VM settings
qm set $LXE_ID --cicustom "vendor=local:snippets/ubuntu.yaml"
qm set $LXE_ID --tags ubuntu-template,noble,cloudinit
qm set ${LXE_ID} --ciuser ${CI_USER} --cipassword "${CI_PASSWORD}"
qm set $LXE_ID --sshkeys ~/ssh.pub
qm set $LXE_ID --ipconfig0 ip=dhcp

# Finally, convert the configured VM into a template for rapid future deployment
echo "Converting VM to template..."
qm template ${LXE_ID}

echo "Template ${LXE_NAME} (LXE_ID: ${LXE_ID}) created successfully."