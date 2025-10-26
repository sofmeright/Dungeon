#!/bin/bash
################################################################################
# Kubernetes Node Graceful Shutdown
#
# Multi-phase shutdown orchestrator:
# 1. Cordon node
# 2. Drain pods (respecting PDBs)
# 3. Stop kubelet
# 4. Unmount volumes in dependency order
# 5. Unmap block devices
# 6. Clean filesystem state
################################################################################

set -euo pipefail

# Configuration
NODE_NAME=$(hostname)
LOG_FILE="/var/log/k8s-shutdown.log"
DRAIN_TIMEOUT=60
GRACE_PERIOD=30
MAX_PHASE_TIMEOUT=90

# Logging with timestamps
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SHUTDOWN] $*" | tee -a "$LOG_FILE"
}

log_phase() {
    echo "" | tee -a "$LOG_FILE"
    log "======================================================================"
    log "PHASE: $*"
    log "======================================================================"
}

# Timeout wrapper for phases
run_with_timeout() {
    local timeout=$1
    shift
    timeout --foreground "$timeout" "$@" || {
        log "WARNING: Phase timed out after ${timeout}s, continuing..."
        return 0
    }
}

################################################################################
# PHASE 1: Cordon Node
################################################################################
phase_cordon() {
    log_phase "1. Cordon Node"

    if /usr/bin/kubectl cordon "$NODE_NAME" 2>&1 | tee -a "$LOG_FILE"; then
        log "✓ Node cordoned successfully"
        return 0
    else
        log "✗ Failed to cordon node (non-fatal)"
        return 0
    fi
}

################################################################################
# PHASE 2: Drain Pods
################################################################################
phase_drain() {
    log_phase "2. Drain Kubernetes Pods"

    log "Starting drain with ${DRAIN_TIMEOUT}s timeout, ${GRACE_PERIOD}s grace period..."

    /usr/bin/kubectl drain "$NODE_NAME" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --grace-period="$GRACE_PERIOD" \
        --timeout="${DRAIN_TIMEOUT}s" \
        --force \
        --disable-eviction 2>&1 | tee -a "$LOG_FILE" || {
        log "WARNING: Drain completed with errors (continuing anyway)"
    }

    log "✓ Drain phase completed"
}

################################################################################
# PHASE 3: Stop Kubelet
################################################################################
phase_stop_kubelet() {
    log_phase "3. Stop Kubelet Service"

    if systemctl is-active --quiet kubelet; then
        log "Stopping kubelet..."
        systemctl stop kubelet 2>&1 | tee -a "$LOG_FILE" || true

        # Wait for kubelet to fully stop
        for i in {1..10}; do
            if ! systemctl is-active --quiet kubelet; then
                log "✓ Kubelet stopped"
                return 0
            fi
            sleep 1
        done

        log "WARNING: Kubelet did not stop cleanly, force killing..."
        pkill -9 kubelet || true
    else
        log "✓ Kubelet already stopped"
    fi
}

################################################################################
# PHASE 4: Unmount Pod Volumes (in reverse dependency order)
################################################################################
phase_unmount_volumes() {
    log_phase "4. Unmount Pod Volumes"

    # Wait for kubelet to release mounts
    log "Waiting 5s for kubelet mount cleanup..."
    sleep 5

    # Get all kubelet mounts in reverse order (children first)
    local mounts
    mounts=$(mount | grep '/var/lib/kubelet/pods' | awk '{print $3}' | sort -r)

    if [ -z "$mounts" ]; then
        log "✓ No kubelet mounts to clean up"
        return 0
    fi

    local mount_count
    mount_count=$(echo "$mounts" | wc -l)
    log "Found $mount_count kubelet mounts to unmount"

    # First pass: Try graceful unmount
    log "Attempting graceful unmount..."
    while IFS= read -r mount; do
        if mountpoint -q "$mount" 2>/dev/null; then
            log "  Unmounting: $mount"
            umount "$mount" 2>/dev/null || {
                log "  └─ Graceful unmount failed, will retry with force"
            }
        fi
    done <<< "$mounts"

    # Second pass: Force + lazy unmount for stubborn mounts
    sleep 2
    mounts=$(mount | grep '/var/lib/kubelet/pods' | awk '{print $3}' | sort -r)

    if [ -n "$mounts" ]; then
        log "Force unmounting remaining mounts..."
        while IFS= read -r mount; do
            if mountpoint -q "$mount" 2>/dev/null; then
                log "  Force unmounting: $mount"
                umount -f -l "$mount" 2>/dev/null || {
                    log "  └─ Force unmount failed (mount may be in use)"
                }
            fi
        done <<< "$mounts"
    fi

    log "✓ Volume unmount phase completed"
}

################################################################################
# PHASE 5: Unmap Block Devices (Ceph RBD, etc.)
################################################################################
phase_unmap_devices() {
    log_phase "5. Unmap Block Devices"

    # Unmap RBD devices
    local rbd_devices
    rbd_devices=$(ls /dev/rbd* 2>/dev/null || true)

    if [ -z "$rbd_devices" ]; then
        log "✓ No RBD devices to unmap"
    else
        log "Unmapping RBD devices..."
        for dev in /dev/rbd*; do
            if [ -b "$dev" ]; then
                log "  Unmapping: $dev"
                rbd unmap "$dev" 2>&1 | tee -a "$LOG_FILE" || {
                    log "  └─ Failed to unmap $dev (non-fatal)"
                }
            fi
        done
        log "✓ RBD devices unmapped"
    fi

    # Additional cleanup for any remaining CSI mounts
    log "Checking for remaining CSI mounts..."
    local csi_mounts
    csi_mounts=$(mount | grep -E 'csi|rbd' | awk '{print $3}' | sort -r || true)

    if [ -n "$csi_mounts" ]; then
        log "Cleaning up CSI mounts..."
        while IFS= read -r mount; do
            if mountpoint -q "$mount" 2>/dev/null; then
                log "  Unmounting CSI mount: $mount"
                umount -f -l "$mount" 2>/dev/null || true
            fi
        done <<< "$csi_mounts"
    fi

    log "✓ Block device cleanup completed"
}

################################################################################
# PHASE 6: Sync Filesystems
################################################################################
phase_sync_fs() {
    log_phase "6. Sync Filesystems"

    log "Syncing all filesystems..."
    sync
    log "✓ Filesystem sync completed"
}

################################################################################
# PHASE 7: Final Cleanup
################################################################################
phase_final_cleanup() {
    log_phase "7. Final Cleanup"

    # Stop containerd if running (prevents mount recreation)
    if systemctl is-active --quiet containerd; then
        log "Stopping containerd..."
        systemctl stop containerd 2>&1 | tee -a "$LOG_FILE" || true
    fi

    # One final aggressive cleanup pass
    log "Final aggressive mount cleanup..."
    for mount in $(mount | grep -E 'kubelet|rbd|ceph|csi' | awk '{print $3}' | sort -r); do
        umount -f -l "$mount" 2>/dev/null || true
    done

    log "✓ Final cleanup completed"
}

################################################################################
# Main Orchestration
################################################################################
main() {
    log ""
    log "######################################################################"
    log "Kubernetes Graceful Shutdown Initiated for: $NODE_NAME"
    log "######################################################################"

    local start_time
    start_time=$(date +%s)

    # Execute phases with timeouts
    # Export variables and functions to sub-shells
    export NODE_NAME LOG_FILE DRAIN_TIMEOUT GRACE_PERIOD MAX_PHASE_TIMEOUT
    export -f log log_phase

    # Use timeout with bash -c to execute functions with time limits
    timeout --foreground $MAX_PHASE_TIMEOUT bash -c "$(declare -f phase_cordon); phase_cordon" || log "WARNING: Cordon phase timed out or failed"
    timeout --foreground $MAX_PHASE_TIMEOUT bash -c "$(declare -f phase_drain); phase_drain" || log "WARNING: Drain phase timed out or failed"
    timeout --foreground 30 bash -c "$(declare -f phase_stop_kubelet); phase_stop_kubelet" || log "WARNING: Stop kubelet phase timed out or failed"
    timeout --foreground 30 bash -c "$(declare -f phase_unmount_volumes); phase_unmount_volumes" || log "WARNING: Unmount volumes phase timed out or failed"
    timeout --foreground 30 bash -c "$(declare -f phase_unmap_devices); phase_unmap_devices" || log "WARNING: Unmap devices phase timed out or failed"
    timeout --foreground 10 bash -c "$(declare -f phase_sync_fs); phase_sync_fs" || log "WARNING: Sync filesystem phase timed out or failed"
    timeout --foreground 20 bash -c "$(declare -f phase_final_cleanup); phase_final_cleanup" || log "WARNING: Final cleanup phase timed out or failed"

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log ""
    log "######################################################################"
    log "Graceful Shutdown Completed in ${duration}s"
    log "Node is ready for shutdown/reboot"
    log "######################################################################"
    log ""
}

# Execute main
main

exit 0
