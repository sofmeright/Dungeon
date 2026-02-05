#!/bin/bash
# Ceph client capabilities reference for dungeon cluster
# Run on a Proxmox/Ceph node
#
# Pools:
#   - dungeon: NVMe-backed RBD pool (default)
#   - dungeon_hdd: HDD-backed RBD pool (bulk storage)
#
# Usage: Run each section as needed, or run the whole script to update all caps

set -e

echo "=== Updating Ceph client capabilities for dungeon cluster ==="

# client.dungeon - used by CSI node plugin for mounting RBD volumes
echo "Updating client.dungeon caps..."
ceph auth caps client.dungeon \
  mon 'allow r, allow command "osd blacklist", allow command "osd blocklist"' \
  osd 'allow class-read object_prefix rbd_children, allow rwx pool=dungeon, allow rwx pool=dungeon_hdd' \
  mgr 'allow rw'

# client.dungeon-provisioner - used by CSI controller for provisioning RBD volumes
echo "Updating client.dungeon-provisioner caps..."
ceph auth caps client.dungeon-provisioner \
  mon 'allow r, allow command "osd blacklist", allow command "osd blocklist"' \
  osd 'allow rwx pool=dungeon, allow rwx pool=dungeon_hdd, allow class-read object_prefix rbd_children, allow class-write object_prefix rbd_children' \
  mgr 'allow rw'

# client.healthchecker - used by rook-ceph operator for health monitoring
echo "Updating client.healthchecker caps..."
ceph auth caps client.healthchecker \
  mon 'allow r, allow command quorum_status, allow command version' \
  mgr 'allow command config' \
  osd 'profile rbd-read-only, allow rwx pool=default.rgw.meta, allow r pool=.rgw.root, allow rw pool=default.rgw.control, allow rx pool=default.rgw.log, allow x pool=default.rgw.buckets.index' \
  mds 'allow *'

echo ""
echo "=== All client capabilities updated ==="
echo ""
echo "Verify with: ceph auth ls | grep -A5 'client\.\(dungeon\|healthchecker\)'"
