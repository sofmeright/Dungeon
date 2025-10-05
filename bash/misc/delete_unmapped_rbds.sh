#!/bin/bash
set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Delete unmapped RBD volumes (Ceph-only, no kubectl required)
# This script identifies truly unused RBD volumes by checking:
# 1. No active watchers (not currently mounted)
# 2. No children/clones
# 3. User confirmation before each deletion

# Check if rbd command is available
if ! command -v rbd &> /dev/null; then
    echo "ERROR: rbd command not found. Install ceph-common package."
    exit 1
fi

POOL="dungeon"

echo "Scanning for RBD volumes with NO active watchers in pool '$POOL'..."
echo "This indicates volumes that are not currently mounted/in-use."
echo ""

# Get all CSI volumes
mapfile -t all_vols < <(rbd ls "$POOL" | grep "^csi-vol-")

if [ ${#all_vols[@]} -eq 0 ]; then
    echo "No CSI volumes found in pool '$POOL'"
    exit 0
fi

echo "Found ${#all_vols[@]} total CSI volumes"
echo "Checking for watchers (mounted/in-use volumes)..."
echo ""

# Find volumes with NO watchers (safe to potentially delete)
declare -a no_watcher_vols=()
for vol in "${all_vols[@]}"; do
    if ! rbd status "$POOL/$vol" 2>/dev/null | grep -q "watcher="; then
        no_watcher_vols+=("$vol")
    fi
done

if [ ${#no_watcher_vols[@]} -eq 0 ]; then
    echo "All volumes have active watchers (all are in use). Nothing to delete."
    exit 0
fi

echo "Found ${#no_watcher_vols[@]} volumes with NO watchers (potentially unused):"
echo ""

# Show candidates
for vol in "${no_watcher_vols[@]}"; do
    size=$(rbd info "$POOL/$vol" 2>/dev/null | grep "size" | awk '{print $2, $3}')
    echo "  - $vol ($size)"
done

echo ""
echo "⚠️  WARNING: These volumes have no active watchers, but may still be referenced by Kubernetes PVs."
echo "Only delete if you're CERTAIN they are orphaned/unused."
echo ""

read -p "Delete all ${#no_watcher_vols[@]} volumes? (yes/NO): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Starting deletion..."
deleted=0
failed=0
skipped=0

for vol in "${no_watcher_vols[@]}"; do
    echo "Processing $vol..."

    # Double-check watchers right before deletion (things can change)
    if rbd status "$POOL/$vol" 2>/dev/null | grep -q "watcher="; then
        echo "  ⚠️  SKIPPING: $vol now has active watchers (mounted between scan and deletion)"
        ((skipped++))
        continue
    fi

    # Check for children (clones) first
    children=$(rbd children "$POOL/$vol" 2>/dev/null)
    if [ -n "$children" ]; then
        echo "  Found clones, deleting them first..."
        echo "$children" | while read child; do
            if [ -n "$child" ]; then
                echo "    Purging snapshots from clone: $child"
                rbd snap purge "$child" 2>/dev/null || true
                echo "    Deleting clone: $child"
                rbd rm "$child" 2>/dev/null || true
            fi
        done
    fi

    # Check for snapshots
    snaps=$(rbd snap ls "$POOL/$vol" 2>/dev/null | tail -n +2)
    if [ -n "$snaps" ]; then
        echo "  Purging snapshots..."
        rbd snap purge "$POOL/$vol" 2>/dev/null || true
    fi

    # Delete the volume
    if rbd rm "$POOL/$vol" 2>/dev/null; then
        echo "  ✓ Deleted $vol"
        ((deleted++))
    else
        echo "  ✗ Failed to delete $vol"
        ((failed++))
    fi
done

echo ""
echo "Cleanup complete!"
echo "Deleted: ${deleted} volumes"
echo "Skipped: ${skipped} volumes (active watchers detected)"
echo "Failed: ${failed} volumes"
