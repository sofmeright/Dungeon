# nano /etc/host
# nano /etc/host.conf
# rm /etc/hostid
# Regen the hostid:
# ??? Fill in
# nano /etc/hostname
# nano /etc/hosts
# nano /etc/network/interfaces
# systemctl restart networking

# pvecm updatecerts --force
# updatecerts --force
# proxmox-backup-manager cert update --force
# systemctl reload proxmox-backup-proxy
# apt install qemu-guest-agent

# nano /etc/samba/.smbcreds
# chmod 600 /etc/samba/.smbcreds

# nano /etc/fstab
# systemctl daemon-reload
# mkdir /mnt/Proxmox_VE_Backup_on_Flashy_Fuchsia
# chmod -R 770 /mnt/Proxmox_VE_Backup_on_Flashy_Fuchsia/
# mount /mnt/Proxmox_VE_Backup_on_Flashy_Fuchsia
# mount -f /mnt/Proxmox_VE_Backup_on_Flashy_Fuchsia


# nano /etc/auto.master
# nano /etc/auto.cifs
# apt update && apt install autofs
# systemctl restart autofs

# proxmox-backup-manager user create proxmox@pam

# proxmox-backup-manager datastore create Proxmox_VE_Backup_on_Flashy_Fuchsia --path /mnt/Proxmox_VE_on_Flashy_Fuchsia
# proxmox-backup-manager datastore create Flashy_Fuchsia_PVE /mnt/Proxmox_VE_Backup_on_Flashy_Fuchsia
# proxmox-backup-manager datastore list

# Beszel install:
# curl -sL https://raw.githubusercontent.com/henrygd/beszel/main/supplemental/scripts/install-agent.sh -o install-agent.sh && chmod +x install-agent.sh && ./install-agent.sh -p 45876 -k "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL5kuNx1mU7U/sDpNuJwzQHKsv6nZ0DC7BXw2TWQ5t6T"

# Oh My ZSH!
# sudo rm -r /home/kai/.oh-my-zsh && sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# rm -r /home/kai/.oh-my-zsh && sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# rm -r /root/.oh-my-zsh && sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"