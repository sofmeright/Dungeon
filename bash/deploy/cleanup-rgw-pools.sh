#!/bin/bash
set -e

echo "=== Complete RGW Cleanup and Reset ==="
echo ""
echo "This script completely removes RGW configuration, users, and pools"
echo "Run this on a Proxmox node with Ceph access"
echo ""
echo "WARNING: This will DELETE ALL RGW data and configuration!"
echo ""
read -p "Type 'yes' to proceed: " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted"
    exit 1
fi

# Configuration
REALM="dungeon"
ZONEGROUP="default"
ZONE="default"
RGW_HOST=$(hostname)

echo ""
echo "Step 1: Stop RGW service"
if systemctl is-active --quiet ceph-radosgw@radosgw.${RGW_HOST}.service; then
    systemctl stop ceph-radosgw@radosgw.${RGW_HOST}.service
    systemctl disable ceph-radosgw@radosgw.${RGW_HOST}.service
    echo "  ✓ RGW service stopped and disabled"
else
    echo "  ⊘ RGW service not running"
fi

echo ""
echo "Step 2: Delete RGW users"
for user in rgw-admin-ops-user; do
    if radosgw-admin user info --uid=$user 2>/dev/null; then
        radosgw-admin user rm --uid=$user --purge-data
        echo "  ✓ Deleted user: $user"
    else
        echo "  ⊘ User $user does not exist"
    fi
done

echo ""
echo "Step 3: Delete period, zone, zonegroup, and realm"
# Delete in reverse order of dependencies
radosgw-admin period delete --period=$(radosgw-admin period get 2>/dev/null | grep '\"id\"' | head -1 | awk -F'"' '{print $4}') 2>/dev/null || echo "  ⊘ No period to delete"
radosgw-admin zone delete --rgw-zone=$ZONE 2>/dev/null && echo "  ✓ Deleted zone: $ZONE" || echo "  ⊘ Zone does not exist"
radosgw-admin zonegroup delete --rgw-zonegroup=$ZONEGROUP 2>/dev/null && echo "  ✓ Deleted zonegroup: $ZONEGROUP" || echo "  ⊘ Zonegroup does not exist"
radosgw-admin realm delete --rgw-realm=$REALM 2>/dev/null && echo "  ✓ Deleted realm: $REALM" || echo "  ⊘ Realm does not exist"

echo ""
echo "Step 4: Delete all RGW pools"
for pool in $(ceph osd pool ls | grep -E "rgw|\.rgw\."); do
    echo "  Deleting pool: $pool"
    ceph osd pool delete "$pool" "$pool" --yes-i-really-really-mean-it
    echo "  ✓ Deleted $pool"
done

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Current pool list:"
ceph osd pool ls
echo ""
echo "Next steps:"
echo "  1. Run setup-ceph-rgw.sh to recreate RGW with clean configuration"
echo ""
