#!/bin/bash
set -e

echo "=== Cleaning up unwanted RGW pools ==="
echo ""
echo "This script removes pools that were auto-created before realm config was applied"
echo "Run this on a Proxmox node with Ceph access"
echo ""

# List of unwanted pools to delete
UNWANTED_POOLS=(
    ".rgw.root"
    "dungeon-rgw.log"
    "dungeon-rgw.control"
    "dungeon-rgw.root"
    "dungeon-rgw.gc"
    "dungeon-rgw.lc"
    "dungeon-rgw.reshard"
    "dungeon-rgw.notif"
)

echo "WARNING: This will DELETE the following pools:"
for pool in "${UNWANTED_POOLS[@]}"; do
    echo "  - $pool"
done
echo ""
echo "Keeping: dungeon, dungeon-rgw, dungeon-rgw-data"
echo ""
read -p "Type 'yes' to proceed: " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted"
    exit 1
fi

echo ""
for pool in "${UNWANTED_POOLS[@]}"; do
    if ceph osd pool ls | grep -q "^${pool}$"; then
        echo "Deleting pool: $pool"
        # Ceph requires pool name to be typed twice as confirmation
        ceph osd pool delete "$pool" "$pool" --yes-i-really-really-mean-it
        echo "  ✓ Deleted $pool"
    else
        echo "  ⊘ Pool $pool does not exist (skipping)"
    fi
done

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Current pool list:"
ceph osd pool ls
echo ""
