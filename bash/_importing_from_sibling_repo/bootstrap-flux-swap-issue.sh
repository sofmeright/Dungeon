  # Disable swap immediately
  sudo swapoff -a

  # Remove swap from /etc/fstab to prevent it from enabling on next boot
  sudo sed -i '/ swap / s/^/#/' /etc/fstab

  # Remove any swap files that may exist
  sudo rm -f /swap.img /swapfile

  # Restart kubelet
  sudo systemctl restart kubelet