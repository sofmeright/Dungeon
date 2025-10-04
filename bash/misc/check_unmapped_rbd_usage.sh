#!/bin/bash
# Check disk usage for unmapped RBD volumes
# Compares current K8s PVs against all Ceph RBDs to find orphaned volumes

# Step 1: Get list of currently mapped volumes from K8s
echo "Getting currently mapped volumes from K8s..."
kubectl get pv -o json | jq -r '.items[].spec.csi.volumeAttributes.imageName // empty' | grep "csi-vol-" | sed 's/csi-vol-//' | sort > current_vols.txt
current_count=$(wc -l < current_vols.txt)
echo "Found ${current_count} currently mapped volumes"

# Step 2: Get all RBD volumes from Ceph (run this where you have rbd access)
echo ""
echo "Getting all RBD volumes from Ceph..."
echo "NOTE: Run 'rbd ls dungeon > all_ceph_rbds.txt' on your Ceph host first"
if [ ! -f all_ceph_rbds.txt ]; then
    echo "ERROR: all_ceph_rbds.txt not found. Run 'rbd ls dungeon > all_ceph_rbds.txt' first"
    exit 1
fi

grep "csi-vol-" all_ceph_rbds.txt | sed 's/csi-vol-//' | sort > all_vols.txt
all_count=$(wc -l < all_vols.txt)
echo "Found ${all_count} total RBD volumes in Ceph"

# Step 3: Find unmapped volumes
echo ""
echo "Finding unmapped volumes..."
comm -23 all_vols.txt current_vols.txt > unmapped_vols.txt
unmapped_count=$(wc -l < unmapped_vols.txt)
echo "Found ${unmapped_count} unmapped volumes"

# Step 4: Get disk usage for unmapped volumes
echo ""
echo "Getting disk usage for unmapped volumes..."
echo "UUID,PROVISIONED,USED" > unmapped_rbd_usage.csv

while IFS= read -r uuid; do
    if [ -n "$uuid" ]; then
        usage=$(rbd disk-usage dungeon/csi-vol-${uuid} --format=json 2>/dev/null)
        if [ $? -eq 0 ]; then
            provisioned=$(echo "$usage" | jq -r '.images[0].provisioned_size // 0')
            used=$(echo "$usage" | jq -r '.images[0].used_size // 0')
            echo "${uuid},${provisioned},${used}" >> unmapped_rbd_usage.csv
        fi
    fi
done < unmapped_vols.txt

echo "Analysis complete. Results saved to unmapped_rbd_usage.csv"
