# Ceph CSI Configuration

## Security Model

This configuration uses **dedicated Ceph users** with minimal privileges instead of admin access:

- **dungeon-provisioner**: Can create/delete volumes in the kubernetes pool only
- **dungeon**: Can mount/unmount volumes to nodes

This follows the principle of least privilege - no admin access from Kubernetes!

## Prerequisites on Proxmox

1. SSH to your Proxmox node and get the required information:

```bash
# Get Ceph cluster ID (you'll need this for config files)
ceph fsid

# Get Ceph monitor IPs
ceph mon dump | grep mon

# Create a dedicated pool for Kubernetes (if not exists)
ceph osd pool create kubernetes 128
rbd pool init kubernetes

# Create the provisioner user (for creating/deleting volumes)
ceph auth get-or-create client.dungeon-provisioner \
  mon 'allow r, allow command "osd blacklist"' \
  osd 'allow rwx pool=kubernetes' \
  mgr 'allow rw'

# Create the mount user (for attaching volumes to nodes)
ceph auth get-or-create client.dungeon \
  mon 'allow r' \
  osd 'allow class-read object_prefix rbd_children, allow rwx pool=kubernetes'

# Get the keys for both users
ceph auth get-key client.dungeon-provisioner
ceph auth get-key client.dungeon

# Verify the users were created with correct permissions
ceph auth get client.dungeon-provisioner
ceph auth get client.dungeon
```

2. Update the files with your actual values:

- **ceph-config.yaml**: Replace cluster ID and monitor IPs
- **ceph-secret.enc.yaml**: Add your Ceph keys
- **storageclass.yaml**: Update cluster ID and pool name

3. Encrypt the secret file with SOPS:

```bash
cd /mnt/c/opt/fluxcd
.sops/bin/sops --encrypt --in-place infrastructure/configs/overlays/production/ceph-csi/ceph-secret.enc.yaml
```

4. Commit and push the changes:

```bash
git add -A
git commit -m "Add Ceph CSI storage configuration"
git push
```

5. Flux will automatically deploy the Ceph CSI driver and create the StorageClass.