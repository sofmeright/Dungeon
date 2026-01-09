#!/bin/bash
#
# galera-heal-node.sh - Heal a specific unhealthy Galera cluster node
#
# This script heals a diverged/split-brain node by:
# 1. Suspending the MariaDB CR (operator stops reconciling)
# 2. Scaling down StatefulSet to release PVCs
# 3. Running helper pods to:
#    - Wipe grastate.dat and galera.cache on storage PVC
#    - Remove 1-bootstrap.cnf from galera config PVC
# 4. Resuming the CR (operator recreates pod, joins via SST)
#
# IMPORTANT: You must identify the bad node yourself first.
# This script does NOT auto-detect - it heals exactly what you specify.
#
# Usage:
#   ./galera-heal-node.sh <mariadb-name> <namespace> <bad-node-number>
#
# Example:
#   # First, check status yourself:
#   kubectl get mariadb osticket-mariadb -n hyrule-castle
#   kubectl get pods -n hyrule-castle -l app.kubernetes.io/instance=osticket-mariadb
#
#   # Check grastate.dat on each node to find the healthy one:
#   kubectl exec osticket-mariadb-1 -n hyrule-castle -c mariadb -- cat /var/lib/mysql/grastate.dat
#
#   # Then heal the specific bad node:
#   ./galera-heal-node.sh osticket-mariadb hyrule-castle 0
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Track state for cleanup
HELPER_POD=""
HELPER_POD_GALERA=""
SUSPENDED=""

cleanup() {
    local exit_code=$?
    # Clean up helper pods
    if [[ -n "${HELPER_POD:-}" ]]; then
        log_info "Cleaning up storage helper pod..."
        kubectl delete pod "${HELPER_POD}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
    fi
    if [[ -n "${HELPER_POD_GALERA:-}" ]]; then
        log_info "Cleaning up galera config helper pod..."
        kubectl delete pod "${HELPER_POD_GALERA}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
    fi
    # On failure, show recovery command
    if [[ ${exit_code} -ne 0 ]] && [[ -n "${SUSPENDED:-}" ]]; then
        log_warn "Script failed while CR was suspended."
        log_warn "Healthy pods still running. To resume operator:"
        log_warn "  kubectl patch mariadb ${MARIADB_NAME} -n ${NAMESPACE} --type=merge -p '{\"spec\":{\"suspend\":false}}'"
    fi
}
trap cleanup EXIT

# Require all 3 arguments
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <mariadb-name> <namespace> <bad-node-number>"
    echo ""
    echo "All arguments are REQUIRED. No auto-detection."
    echo ""
    echo "Example:"
    echo "  $0 osticket-mariadb hyrule-castle 0"
    echo ""
    echo "First identify the bad node by checking grastate.dat:"
    echo "  kubectl exec <mariadb>-<N> -n <namespace> -c mariadb -- cat /var/lib/mysql/grastate.dat"
    exit 1
fi

MARIADB_NAME="$1"
NAMESPACE="$2"
BAD_NODE="$3"
TARGET_POD="${MARIADB_NAME}-${BAD_NODE}"
TARGET_PVC="storage-${MARIADB_NAME}-${BAD_NODE}"
GALERA_PVC="galera-${MARIADB_NAME}-${BAD_NODE}"

log_info "=== Galera Node Healer ==="
log_info "MariaDB: ${MARIADB_NAME}"
log_info "Namespace: ${NAMESPACE}"
log_info "Bad node: ${TARGET_POD}"

# Verify MariaDB CR exists
if ! kubectl get mariadb "${MARIADB_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    log_error "MariaDB ${MARIADB_NAME} not found in namespace ${NAMESPACE}"
    exit 1
fi

# Verify target storage PVC exists
if ! kubectl get pvc "${TARGET_PVC}" -n "${NAMESPACE}" &>/dev/null; then
    log_error "Storage PVC ${TARGET_PVC} not found. Cannot heal non-existent node."
    exit 1
fi

# Check if galera config PVC exists (operator creates this for galera clusters)
HAS_GALERA_PVC="false"
if kubectl get pvc "${GALERA_PVC}" -n "${NAMESPACE}" &>/dev/null; then
    HAS_GALERA_PVC="true"
    log_info "Galera config PVC found: ${GALERA_PVC}"
else
    log_warn "Galera config PVC ${GALERA_PVC} not found (may be using ConfigMap instead)"
fi

# Get current state
CURRENT_REPLICAS=$(kubectl get mariadb "${MARIADB_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
READY_REPLICAS=$(kubectl get sts "${MARIADB_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

log_info "Current state: ${READY_REPLICAS}/${CURRENT_REPLICAS} ready"

# Check if already suspended
ALREADY_SUSPENDED=$(kubectl get mariadb "${MARIADB_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.suspend}' 2>/dev/null || echo "false")
if [[ "${ALREADY_SUSPENDED}" == "true" ]]; then
    log_warn "MariaDB CR is already suspended!"
fi

# Check target pod status
TARGET_STATUS=$(kubectl get pod "${TARGET_POD}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
TARGET_READY=$(kubectl get pod "${TARGET_POD}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[?(@.name=="mariadb")].ready}' 2>/dev/null || echo "false")
log_info "Target pod status: ${TARGET_STATUS}, ready: ${TARGET_READY}"

if [[ "${TARGET_READY}" == "true" ]]; then
    log_warn "WARNING: Target pod ${TARGET_POD} appears healthy!"
    log_warn "Are you sure you want to wipe its grastate.dat?"
fi

# Show current grastate if accessible
log_info "Checking grastate.dat on target node..."
TARGET_GRASTATE=$(kubectl exec "${TARGET_POD}" -n "${NAMESPACE}" -c mariadb -- cat /var/lib/mysql/grastate.dat 2>/dev/null || echo "INACCESSIBLE")
if [[ "${TARGET_GRASTATE}" != "INACCESSIBLE" ]]; then
    echo "--- Target node grastate.dat ---"
    echo "${TARGET_GRASTATE}"
    echo "---"
fi

# Determine if we can avoid full scale-down
# StatefulSets delete from the end, so we can only cleanly remove the highest-numbered pod
SCALE_TARGET=$((CURRENT_REPLICAS - 1))
if [[ "${BAD_NODE}" -eq "${SCALE_TARGET}" ]]; then
    # Bad node is the highest - we can scale to N-1 without affecting lower pods
    SCALE_STRATEGY="partial"
    DOWNTIME_MSG="Node ${BAD_NODE} only - lower pods stay running"
else
    # Bad node is NOT the highest - must scale to 0
    SCALE_STRATEGY="full"
    DOWNTIME_MSG="Brief full cluster restart required (StatefulSet limitation)"
fi

# Show plan
echo ""
log_info "=== Plan ==="
log_info "1. Suspend MariaDB CR (operator stops recovery)"
log_info "2. Scale down StatefulSet to release PVCs"
log_info "3. Wipe grastate.dat + galera.cache on storage PVC"
if [[ "${HAS_GALERA_PVC}" == "true" ]]; then
    log_info "4. Remove bootstrap config from galera PVC"
    log_info "5. Scale back up, resume CR (pod rejoins via SST)"
else
    log_info "4. Scale back up, resume CR (pod rejoins via SST)"
fi
echo ""
if [[ "${SCALE_STRATEGY}" == "partial" ]]; then
    log_info "Downtime: ${DOWNTIME_MSG}"
else
    log_warn "Downtime: ${DOWNTIME_MSG}"
    log_warn "StatefulSets can only remove pods from the end (highest number first)."
    log_warn "To fix node ${BAD_NODE}, we must scale down past it."
fi
echo ""

read -p "Type 'yes' to proceed: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    log_info "Aborted."
    exit 0
fi

# === STEP 1: Suspend the MariaDB CR ===
log_info "Step 1: Suspending MariaDB CR..."

kubectl patch mariadb "${MARIADB_NAME}" -n "${NAMESPACE}" \
    --type=merge -p '{"spec":{"suspend":true}}'
SUSPENDED=1

# Wait for suspension to take effect
sleep 2
log_info "CR suspended. Operator will not reconcile."

# === STEP 2: Scale down to release PVC ===
log_info "Step 2: Scaling down StatefulSet..."

# Scale based on strategy
if [[ "${SCALE_STRATEGY}" == "partial" ]]; then
    # Scale to N-1 (removes only the highest pod)
    kubectl scale sts "${MARIADB_NAME}" -n "${NAMESPACE}" --replicas="${BAD_NODE}"
else
    # Scale to 0 (removes all pods)
    kubectl scale sts "${MARIADB_NAME}" -n "${NAMESPACE}" --replicas=0
fi

# Wait for target pod to be gone
TIMEOUT=90
ELAPSED=0
while kubectl get pod "${TARGET_POD}" -n "${NAMESPACE}" &>/dev/null; do
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        log_warn "Pod stuck terminating, force deleting..."
        kubectl delete pod "${TARGET_POD}" -n "${NAMESPACE}" --force --grace-period=0 2>/dev/null || true
        sleep 5
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    if [[ $((ELAPSED % 15)) -eq 0 ]]; then
        echo "Waiting for ${TARGET_POD} to terminate... (${ELAPSED}s)"
    fi
done
log_info "Pod terminated, PVCs released."

# === STEP 3: Create helper pod to fix storage PVC (grastate + galera.cache) ===
log_info "Step 3: Wiping grastate.dat and galera.cache..."

HELPER_POD="${MARIADB_NAME}-heal-storage-${BAD_NODE}-$$"

cat <<'EOFYAML' | sed "s/HELPER_POD_PLACEHOLDER/${HELPER_POD}/g; s/NAMESPACE_PLACEHOLDER/${NAMESPACE}/g; s/TARGET_PVC_PLACEHOLDER/${TARGET_PVC}/g" | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: HELPER_POD_PLACEHOLDER
  namespace: NAMESPACE_PLACEHOLDER
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 0
  containers:
  - name: healer
    image: docker.io/library/busybox:latest
    command: ["sh", "-c", "set -e; echo '=== Current grastate.dat ==='; cat /var/lib/mysql/grastate.dat 2>/dev/null || echo 'not found'; echo ''; echo '=== Wiping grastate.dat ==='; printf '%s\\n' '# GALERA saved state' 'version: 2.1' 'uuid:    00000000-0000-0000-0000-000000000000' 'seqno:   -1' 'safe_to_bootstrap: 0' > /var/lib/mysql/grastate.dat; echo 'New grastate.dat:'; cat /var/lib/mysql/grastate.dat; echo ''; echo '=== Removing galera.cache (forces full SST) ==='; rm -f /var/lib/mysql/galera.cache; echo 'galera.cache removed'; echo '=== Done! ==='"]
    volumeMounts:
    - name: storage
      mountPath: /var/lib/mysql
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: TARGET_PVC_PLACEHOLDER
EOFYAML

# Wait for helper to complete
log_info "Waiting for storage helper pod..."
TIMEOUT=90
ELAPSED=0
while true; do
    STATUS=$(kubectl get pod "${HELPER_POD}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "${STATUS}" == "Succeeded" ]]; then
        log_info "Storage PVC cleaned successfully!"
        break
    elif [[ "${STATUS}" == "Failed" ]]; then
        log_error "Storage helper pod FAILED!"
        echo "--- Pod description ---"
        kubectl describe pod "${HELPER_POD}" -n "${NAMESPACE}" 2>/dev/null | tail -30 || true
        echo "--- Pod logs ---"
        kubectl logs "${HELPER_POD}" -n "${NAMESPACE}" 2>/dev/null || true
        exit 1
    elif [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        log_error "Timeout waiting for storage helper pod!"
        kubectl describe pod "${HELPER_POD}" -n "${NAMESPACE}" 2>/dev/null | tail -20 || true
        exit 1
    fi
    if [[ $((ELAPSED % 10)) -eq 0 ]] && [[ ${ELAPSED} -gt 0 ]]; then
        echo "Waiting for storage helper... status=${STATUS} (${ELAPSED}s)"
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

# Show helper pod logs
kubectl logs "${HELPER_POD}" -n "${NAMESPACE}" 2>/dev/null || true

# Cleanup storage helper pod
kubectl delete pod "${HELPER_POD}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
unset HELPER_POD
sleep 2

# === STEP 4: Remove bootstrap config from galera PVC (if exists) ===
if [[ "${HAS_GALERA_PVC}" == "true" ]]; then
    log_info "Step 4: Removing bootstrap config from galera PVC..."

    HELPER_POD_GALERA="${MARIADB_NAME}-heal-galera-${BAD_NODE}-$$"

    cat <<'EOFYAML' | sed "s/HELPER_POD_PLACEHOLDER/${HELPER_POD_GALERA}/g; s/NAMESPACE_PLACEHOLDER/${NAMESPACE}/g; s/GALERA_PVC_PLACEHOLDER/${GALERA_PVC}/g" | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: HELPER_POD_PLACEHOLDER
  namespace: NAMESPACE_PLACEHOLDER
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 0
  containers:
  - name: healer
    image: docker.io/library/busybox:latest
    command: ["sh", "-c", "set -e; echo '=== Current galera config ==='; ls -la /galera/; echo ''; if [ -f /galera/1-bootstrap.cnf ]; then echo '=== Found bootstrap config ==='; cat /galera/1-bootstrap.cnf; echo ''; echo '=== Removing 1-bootstrap.cnf ==='; rm -f /galera/1-bootstrap.cnf; echo 'Bootstrap config removed!'; else echo 'No 1-bootstrap.cnf found (OK)'; fi; echo ''; echo '=== Final galera config ==='; ls -la /galera/; echo '=== Done! ==='"]
    volumeMounts:
    - name: galera
      mountPath: /galera
  volumes:
  - name: galera
    persistentVolumeClaim:
      claimName: GALERA_PVC_PLACEHOLDER
EOFYAML

    # Wait for galera helper to complete
    log_info "Waiting for galera config helper pod..."
    TIMEOUT=90
    ELAPSED=0
    while true; do
        STATUS=$(kubectl get pod "${HELPER_POD_GALERA}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "${STATUS}" == "Succeeded" ]]; then
            log_info "Galera config PVC cleaned successfully!"
            break
        elif [[ "${STATUS}" == "Failed" ]]; then
            log_error "Galera config helper pod FAILED!"
            echo "--- Pod description ---"
            kubectl describe pod "${HELPER_POD_GALERA}" -n "${NAMESPACE}" 2>/dev/null | tail -30 || true
            echo "--- Pod logs ---"
            kubectl logs "${HELPER_POD_GALERA}" -n "${NAMESPACE}" 2>/dev/null || true
            exit 1
        elif [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
            log_error "Timeout waiting for galera config helper pod!"
            kubectl describe pod "${HELPER_POD_GALERA}" -n "${NAMESPACE}" 2>/dev/null | tail -20 || true
            exit 1
        fi
        if [[ $((ELAPSED % 10)) -eq 0 ]] && [[ ${ELAPSED} -gt 0 ]]; then
            echo "Waiting for galera config helper... status=${STATUS} (${ELAPSED}s)"
        fi
        sleep 3
        ELAPSED=$((ELAPSED + 3))
    done

    # Show helper pod logs
    kubectl logs "${HELPER_POD_GALERA}" -n "${NAMESPACE}" 2>/dev/null || true

    # Cleanup galera helper pod
    kubectl delete pod "${HELPER_POD_GALERA}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
    unset HELPER_POD_GALERA
    sleep 2
fi

# === STEP 5: Scale back up and resume CR ===
log_info "Step 5: Restoring cluster..."

# Delete stale recovery pods to force fresh detection
log_info "Clearing stale recovery pods..."
kubectl delete pod -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${MARIADB_NAME}" --field-selector="status.phase!=Running" --force --grace-period=0 2>/dev/null || true
kubectl delete pod -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${MARIADB_NAME},k8s.mariadb.com/recovery=true" --force --grace-period=0 2>/dev/null || true
sleep 2

# Scale back to original
kubectl scale sts "${MARIADB_NAME}" -n "${NAMESPACE}" --replicas="${CURRENT_REPLICAS}"

# Resume CR
kubectl patch mariadb "${MARIADB_NAME}" -n "${NAMESPACE}" \
    --type=merge -p '{"spec":{"suspend":false}}'
unset SUSPENDED

log_info "CR resumed. Waiting for ${TARGET_POD} to rejoin cluster..."

# Wait for pod to come back
TIMEOUT=180
ELAPSED=0
while true; do
    if kubectl get pod "${TARGET_POD}" -n "${NAMESPACE}" &>/dev/null; then
        READY=$(kubectl get pod "${TARGET_POD}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[?(@.name=="mariadb")].ready}' 2>/dev/null || echo "false")
        PHASE=$(kubectl get pod "${TARGET_POD}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [[ "${READY}" == "true" ]]; then
            log_info "${TARGET_POD} is ready!"
            break
        fi
        echo "Pod status: ${PHASE}, ready: ${READY}"
    else
        echo "Waiting for pod to be created..."
    fi
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        log_warn "Timeout waiting for ${TARGET_POD} to become ready."
        log_warn "Check pod status manually - SST may still be in progress."
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

# Final status
echo ""
log_info "=== Final Status ==="
kubectl get mariadb "${MARIADB_NAME}" -n "${NAMESPACE}" 2>/dev/null || true
kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${MARIADB_NAME}"

# Check grastate on healed node
echo ""
log_info "Checking grastate.dat on healed node..."
sleep 3
NEW_GRASTATE=$(kubectl exec "${TARGET_POD}" -n "${NAMESPACE}" -c mariadb -- cat /var/lib/mysql/grastate.dat 2>/dev/null || echo "INACCESSIBLE")
if [[ "${NEW_GRASTATE}" != "INACCESSIBLE" ]]; then
    echo "--- Healed node grastate.dat ---"
    echo "${NEW_GRASTATE}"
    echo "---"
fi

log_info "Done!"
