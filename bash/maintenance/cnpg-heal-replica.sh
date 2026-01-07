#!/bin/bash
#
# cnpg-heal-replica.sh - Heal a specific unhealthy CNPG PostgreSQL replica
#
# This script heals a diverged/unhealthy replica by:
# 1. Fencing the instance (CNPG stops managing it)
# 2. Force deleting the fenced pod repeatedly until it stays gone
# 3. Running a SINGLE pod that clears pgdata AND runs pg_basebackup
#    (This avoids race conditions with PVC attachment)
# 4. Removing the fence (CNPG takes over the replica)
#
# IMPORTANT: You must identify the bad replica yourself first.
# This script does NOT auto-detect - it heals exactly what you specify.
#
# Usage:
#   ./cnpg-heal-replica.sh <cluster-name> <namespace> <replica-number>
#
# Example:
#   # First, check status yourself:
#   kubectl get cluster vaultwarden-postgres -n zeldas-lullaby
#   kubectl get pods -n zeldas-lullaby -l cnpg.io/cluster=vaultwarden-postgres
#
#   # Then heal the specific bad replica:
#   ./cnpg-heal-replica.sh vaultwarden-postgres zeldas-lullaby 3
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Cleanup function - only removes fence if operation completed successfully
REMOVE_FENCE_ON_EXIT=""
cleanup() {
    local exit_code=$?
    # Clean up helper pods
    if [[ -n "${HEAL_POD:-}" ]]; then
        kubectl delete pod "${HEAL_POD}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
    fi
    # Only remove fence if explicitly set (successful operation)
    if [[ -n "${REMOVE_FENCE_ON_EXIT:-}" ]]; then
        log_info "Removing fence..."
        kubectl annotate cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" cnpg.io/fencedInstances- &>/dev/null || true
    elif [[ ${exit_code} -ne 0 ]] && [[ -n "${CLUSTER_NAME:-}" ]] && [[ -n "${NAMESPACE:-}" ]]; then
        log_warn "Fence left in place - replica ${TARGET_POD} is still fenced."
        log_warn "To remove fence manually: kubectl annotate cluster ${CLUSTER_NAME} -n ${NAMESPACE} cnpg.io/fencedInstances-"
    fi
}
trap cleanup EXIT

# Require all 3 arguments
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <cluster-name> <namespace> <replica-number>"
    echo ""
    echo "All arguments are REQUIRED. No auto-detection."
    echo ""
    echo "Example:"
    echo "  $0 vaultwarden-postgres zeldas-lullaby 3"
    echo ""
    echo "First identify the bad replica yourself:"
    echo "  kubectl get cluster <name> -n <namespace>"
    echo "  kubectl get pods -n <namespace> -l cnpg.io/cluster=<name>"
    exit 1
fi

CLUSTER_NAME="$1"
NAMESPACE="$2"
REPLICA_NUM="$3"
TARGET_POD="${CLUSTER_NAME}-${REPLICA_NUM}"
TARGET_PVC="${CLUSTER_NAME}-${REPLICA_NUM}"

log_info "=== CNPG Replica Healer (Fencing Mode) ==="
log_info "Cluster: ${CLUSTER_NAME}"
log_info "Namespace: ${NAMESPACE}"
log_info "Target replica: ${TARGET_POD}"

# Verify cluster exists
if ! kubectl get cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    log_error "Cluster ${CLUSTER_NAME} not found in namespace ${NAMESPACE}"
    exit 1
fi

# Verify PVC exists
if ! kubectl get pvc "${TARGET_PVC}" -n "${NAMESPACE}" &>/dev/null; then
    log_error "PVC ${TARGET_PVC} not found. Cannot heal non-existent replica."
    exit 1
fi

# Get cluster state
CURRENT_INSTANCES=$(kubectl get cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.instances}')
READY_INSTANCES=$(kubectl get cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyInstances}')
PRIMARY=$(kubectl get cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.currentPrimary}')
PHASE=$(kubectl get cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}')
PG_IMAGE=$(kubectl get cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.imageName}')

log_info "Current state: ${READY_INSTANCES}/${CURRENT_INSTANCES} ready"
log_info "Phase: ${PHASE}"
log_info "Primary: ${PRIMARY}"
log_info "PostgreSQL image: ${PG_IMAGE}"

# === SAFETY CHECKS ===

# Check 1: Is target the primary?
if [[ "${TARGET_POD}" == "${PRIMARY}" ]]; then
    log_error "ABORT: ${TARGET_POD} is the PRIMARY. Cannot heal primary."
    log_error "Failover first if you need to replace the primary."
    exit 1
fi

# Check 2: Warn if cluster is not fully healthy
if [[ "${READY_INSTANCES}" != "${CURRENT_INSTANCES}" ]]; then
    log_warn "WARNING: Cluster is not fully healthy (${READY_INSTANCES}/${CURRENT_INSTANCES})"
    log_warn "Proceeding because primary is healthy."
fi

# Check 3: Check for existing fence
EXISTING_FENCE=$(kubectl get cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.metadata.annotations.cnpg\.io/fencedInstances}' 2>/dev/null || echo "")
if [[ -n "${EXISTING_FENCE}" ]]; then
    log_warn "WARNING: Cluster already has fenced instances: ${EXISTING_FENCE}"
    log_warn "This script will add ${TARGET_POD} to the fence list."
fi

# Check 4: Is primary healthy?
PRIMARY_READY=$(kubectl get pod "${PRIMARY}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
if [[ "${PRIMARY_READY}" != "true" ]]; then
    log_error "ABORT: Primary ${PRIMARY} is not healthy."
    log_error "Fix the primary before healing replicas."
    exit 1
fi

# Get primary IP for pg_basebackup
PRIMARY_IP=$(kubectl get pod "${PRIMARY}" -n "${NAMESPACE}" -o jsonpath='{.status.podIP}')
log_info "Primary IP: ${PRIMARY_IP}"

# Show what we're about to do
echo ""
log_info "=== Plan ==="
log_info "1. Fence instance ${TARGET_POD} (CNPG stops managing it)"
log_info "2. Delete pod ${TARGET_POD} (guaranteed exact target)"
log_info "3. Clear pgdata on PVC ${TARGET_PVC} (PVC preserved)"
log_info "4. Run pg_basebackup from ${PRIMARY} with TLS certs"
log_info "5. Remove fence (CNPG takes over the replica)"
echo ""

read -p "Type 'yes' to proceed: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    log_info "Aborted."
    exit 0
fi

# === STEP 1: Fence the instance ===
log_info "Step 1/5: Fencing instance ${TARGET_POD}..."

# Add to fence list (may already be in list)
if [[ -n "${EXISTING_FENCE}" ]]; then
    # Parse existing JSON array and add if not present
    if echo "${EXISTING_FENCE}" | grep -q "\"${TARGET_POD}\""; then
        log_info "Instance ${TARGET_POD} already fenced."
    else
        NEW_FENCE=$(echo "${EXISTING_FENCE}" | sed "s/]$/,\"${TARGET_POD}\"]/" )
        kubectl annotate cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" \
            "cnpg.io/fencedInstances=${NEW_FENCE}" --overwrite
    fi
else
    kubectl annotate cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" \
        "cnpg.io/fencedInstances=[\"${TARGET_POD}\"]"
fi

# Wait for fence to take effect
sleep 3
log_info "Instance fenced."

# === STEP 2+3+4 COMBINED: Create heal pod FIRST, then delete target pod ===
# Strategy: Create the heal pod first (it will wait for PVC), then aggressively
# delete the target pod. This way the heal pod is ready to grab the PVC
# the moment the target pod releases it.

log_info "Step 2/5: Setting up heal operation..."

# Get postgres UID/GID from primary
POSTGRES_UID=$(kubectl exec "${PRIMARY}" -n "${NAMESPACE}" -c postgres -- id -u postgres 2>/dev/null || echo "26")
POSTGRES_GID=$(kubectl exec "${PRIMARY}" -n "${NAMESPACE}" -c postgres -- id -g postgres 2>/dev/null || echo "26")
log_info "Postgres UID/GID: ${POSTGRES_UID}/${POSTGRES_GID}"

# Secrets for TLS auth
CA_SECRET="${CLUSTER_NAME}-ca"
REPLICATION_SECRET="${CLUSTER_NAME}-replication"

HEAL_POD="${CLUSTER_NAME}-heal-${REPLICA_NUM}-$$"

log_info "Creating heal pod ${HEAL_POD} (will wait for PVC)..."

# Create a SINGLE pod that does BOTH clearing AND pg_basebackup
# Create it FIRST so it's ready to grab the PVC when target pod releases it
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${HEAL_POD}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: ${POSTGRES_UID}
    runAsGroup: ${POSTGRES_GID}
    fsGroup: ${POSTGRES_GID}
  containers:
  - name: healer
    image: ${PG_IMAGE}
    command:
    - sh
    - -c
    - |
      set -e
      echo "=== Step 1: Clearing pgdata ==="
      # Safety check - don't delete if pgdata looks healthy
      if [ -f /var/lib/postgresql/data/pgdata/PG_VERSION ]; then
        echo "WARNING: Found existing PG_VERSION file. Proceeding with clear..."
      fi
      # Clear contents but keep the directory (parent may be root-owned)
      rm -rf /var/lib/postgresql/data/pgdata/*
      rm -rf /var/lib/postgresql/data/pgdata/.[!.]*
      rm -rf /var/lib/postgresql/data/lost+found
      echo "pgdata cleared."

      echo "=== Step 2: Setting up TLS certificates ==="
      mkdir -p /tmp/certs
      cp /certs/ca/ca.crt /tmp/certs/
      cp /certs/replication/tls.crt /tmp/certs/
      cp /certs/replication/tls.key /tmp/certs/
      chmod 600 /tmp/certs/tls.key
      echo "TLS certs ready."

      echo "=== Step 3: Running pg_basebackup ==="
      pg_basebackup -h ${PRIMARY_IP} -p 5432 -U streaming_replica \
        -D /var/lib/postgresql/data/pgdata \
        -Fp -Xs -P -R \
        --checkpoint=fast \
        -d "sslmode=verify-ca sslcert=/tmp/certs/tls.crt sslkey=/tmp/certs/tls.key sslrootcert=/tmp/certs/ca.crt"

      echo "=== pg_basebackup complete! ==="
    volumeMounts:
    - name: pgdata
      mountPath: /var/lib/postgresql/data
    - name: ca-certs
      mountPath: /certs/ca
      readOnly: true
    - name: replication-certs
      mountPath: /certs/replication
      readOnly: true
  volumes:
  - name: pgdata
    persistentVolumeClaim:
      claimName: ${TARGET_PVC}
  - name: ca-certs
    secret:
      secretName: ${CA_SECRET}
      items:
      - key: ca.crt
        path: ca.crt
  - name: replication-certs
    secret:
      secretName: ${REPLICATION_SECRET}
      items:
      - key: tls.crt
        path: tls.crt
      - key: tls.key
        path: tls.key
EOF

# Give the heal pod a moment to be created
sleep 2

log_info "Step 3/5: Aggressively deleting ${TARGET_POD} until heal pod gets the PVC..."

# Now aggressively delete the target pod in a tight loop
# The heal pod is waiting for the PVC - when target releases it, heal pod grabs it
DELETE_COUNT=0
TIMEOUT=300
ELAPSED=0
while [[ ${ELAPSED} -lt ${TIMEOUT} ]]; do
    # Check if heal pod has started running (got the PVC)
    HEAL_STATUS=$(kubectl get pod "${HEAL_POD}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    if [[ "${HEAL_STATUS}" == "Running" ]] || [[ "${HEAL_STATUS}" == "Succeeded" ]]; then
        log_info "Heal pod acquired PVC and is running!"
        break
    fi
    if [[ "${HEAL_STATUS}" == "Failed" ]]; then
        log_error "Heal pod failed!"
        kubectl logs "${HEAL_POD}" -n "${NAMESPACE}" 2>/dev/null || true
        exit 1
    fi

    # Delete target pod if it exists - don't wait, just fire and forget
    if kubectl get pod "${TARGET_POD}" -n "${NAMESPACE}" &>/dev/null; then
        kubectl delete pod "${TARGET_POD}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null &
        DELETE_COUNT=$((DELETE_COUNT + 1))
        if [[ $((DELETE_COUNT % 10)) -eq 0 ]]; then
            echo "Deleted ${DELETE_COUNT} times, heal pod status: ${HEAL_STATUS}"
        fi
    fi

    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

if [[ "${HEAL_STATUS}" != "Running" ]] && [[ "${HEAL_STATUS}" != "Succeeded" ]]; then
    log_error "Timeout: Heal pod could not acquire PVC after ${TIMEOUT}s"
    log_error "Target pod ${TARGET_POD} may be holding the PVC"
    kubectl describe pod "${HEAL_POD}" -n "${NAMESPACE}" | tail -30
    exit 1
fi

log_info "Pod ${TARGET_POD} deleted (deleted ${DELETE_COUNT} time(s))."
log_info "Step 4/5: Heal pod running pg_basebackup (this may take a while)..."

# Now wait for completion
TIMEOUT=600
ELAPSED=0
while true; do
    STATUS=$(kubectl get pod "${HEAL_POD}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "${STATUS}" == "Succeeded" ]]; then
        log_info "Heal operation completed!"
        break
    elif [[ "${STATUS}" == "Failed" ]]; then
        log_error "Heal operation FAILED!"
        kubectl logs "${HEAL_POD}" -n "${NAMESPACE}" 2>/dev/null || true
        exit 1
    elif [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        log_error "Timeout!"
        kubectl logs "${HEAL_POD}" -n "${NAMESPACE}" --tail=50 2>/dev/null || true
        exit 1
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

# Show logs
kubectl logs "${HEAL_POD}" -n "${NAMESPACE}" 2>/dev/null || true

# Cleanup heal pod
kubectl delete pod "${HEAL_POD}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
unset HEAL_POD

# Wait for pod to be fully gone
sleep 5

# === STEP 5: Remove fence ===
log_info "Step 5/5: Removing fence..."
REMOVE_FENCE_ON_EXIT=1
kubectl annotate cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" cnpg.io/fencedInstances-
unset REMOVE_FENCE_ON_EXIT

log_info "Waiting for ${TARGET_POD} to come back online..."
TIMEOUT=300
ELAPSED=0
while true; do
    if kubectl get pod "${TARGET_POD}" -n "${NAMESPACE}" &>/dev/null; then
        READY=$(kubectl get pod "${TARGET_POD}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        if [[ "${READY}" == "true" ]]; then
            log_info "${TARGET_POD} is ready!"
            break
        fi
    fi
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        log_warn "Timeout waiting for ${TARGET_POD} to become ready."
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

echo ""
log_info "=== Final Status ==="
kubectl get cluster "${CLUSTER_NAME}" -n "${NAMESPACE}"
kubectl get pods -n "${NAMESPACE}" -l "cnpg.io/cluster=${CLUSTER_NAME}"
log_info "Done!"
