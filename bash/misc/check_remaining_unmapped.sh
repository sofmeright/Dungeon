#!/bin/bash
# Check which unmapped volumes still exist after deletion attempt

echo "Checking remaining unmapped volumes..."
echo ""

remaining=0
echo "UUID" > remaining_unmapped_vols.txt

while IFS= read -r uuid; do
    if [ -n "$uuid" ]; then
        if rbd info dungeon/csi-vol-${uuid} &>/dev/null; then
            echo "csi-vol-${uuid} still exists"
            echo "${uuid}" >> remaining_unmapped_vols.txt
            ((remaining++))
        fi
    fi
done < unmapped_vols.txt

echo ""
echo "Remaining unmapped volumes: ${remaining}"
echo "List saved to: remaining_unmapped_vols.txt"

if [ $remaining -gt 0 ]; then
    echo ""
    echo "Checking why they failed..."
    tail -n +2 remaining_unmapped_vols.txt | while read uuid; do
        echo ""
        echo "=== csi-vol-${uuid} ==="
        rbd info dungeon/csi-vol-${uuid}
        echo "Snapshots:"
        rbd snap ls dungeon/csi-vol-${uuid}
        echo "Children:"
        rbd children dungeon/csi-vol-${uuid} 2>&1 || echo "No children"
    done
fi
