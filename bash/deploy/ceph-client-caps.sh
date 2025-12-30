#!/bin/bash
# Ceph client capabilities reference for dungeon cluster
# Run on a Proxmox/Ceph node
#
# Pools:
#   - dungeon: NVMe-backed RBD pool (default)
#   - dungeon_hdd: HDD-backed RBD pool (bulk storage)

# client.dungeon - used by CSI node plugin for mounting
ceph auth caps client.dungeon \
  mon 'allow r' \
  osd 'allow class-read object_prefix rbd_children, allow rwx pool=dungeon, allow rwx pool=dungeon_hdd' \
  mgr 'allow rw'

# client.dungeon-provisioner - used by CSI controller for provisioning
ceph auth caps client.dungeon-provisioner \
  mon 'allow r, allow command "osd blacklist"' \
  osd 'allow rwx pool=dungeon, allow rwx pool=dungeon_hdd, allow class-read object_prefix rbd_children, allow class-write object_prefix rbd_children' \
  mgr 'allow rw'
