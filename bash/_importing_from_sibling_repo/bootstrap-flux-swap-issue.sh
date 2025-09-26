  # Disable swap immediately
  sudo swapoff -a

  # Remove swap from /etc/fstab to prevent it from enabling on next boot
  sudo sed -i '/ swap / s/^/#/' /etc/fstab

  # Restart kubelet
  sudo systemctl restart kubelet