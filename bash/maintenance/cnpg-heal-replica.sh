#!/bin/bash
#
# cnpg-heal-replica.sh - Heal a specific unhealthy CNPG PostgreSQL replica
#
# This script heals a diverged/unhealthy replica by:
# 1. Scaling down the cluster to remove the specified replica
# 2. Clearing pgdata on the PVC (NOT deleting the PVC)
# 3. Running pg_basebackup to repopulate from primary
# 4. Scaling back up
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

log_info "=== CNPG Replica Healer ==="
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

log_info "Current state: ${READY_INSTANCES}/${CURRENT_INSTANCES} ready"
log_info "Phase: ${PHASE}"
log_info "Primary: ${PRIMARY}"

# === SAFETY CHECKS ===

# Check 1: Is target the primary?
if [[ "${TARGET_POD}" == "${PRIMARY}" ]]; then
    log_error "ABORT: ${TARGET_POD} is the PRIMARY. Cannot heal primary."
    log_error "Failover first if you need to replace the primary."
    exit 1
fi

# Check 2: Is cluster in a bad state?
if [[ "${PHASE}" == "Failing over" ]] || [[ "${PHASE}" == "Setting up primary" ]]; then
    log_error "ABORT: Cluster is in '${PHASE}' state."
    log_error "Wait for cluster to stabilize before healing replicas."
    exit 1
fi

# Check 3: Do we have enough healthy instances?
if [[ "${READY_INSTANCES}" -lt 2 ]]; then
    log_error "ABORT: Only ${READY_INSTANCES} healthy instance(s)."
    log_error "Need at least 2 healthy instances before healing a replica."
    log_error "Fix the primary or other replicas first."
    exit 1
fi

# Check 4: Is primary healthy?
PRIMARY_READY=$(kubectl get pod "${PRIMARY}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
if [[ "${PRIMARY_READY}" != "true" ]]; then
    log_error "ABORT: Primary ${PRIMARY} is not healthy."
    log_error "Fix the primary before healing replicas."
    exit 1
fi

# Check 5: Warn if cluster is not fully healthy
if [[ "${READY_INSTANCES}" != "${CURRENT_INSTANCES}" ]]; then
    log_warn "WARNING: Cluster is not fully healthy (${READY_INSTANCES}/${CURRENT_INSTANCES})"
    log_warn "Proceeding because primary is healthy and we have ${READY_INSTANCES} ready instances."
fi

# Show what we're about to do
echo ""
log_info "=== Plan ==="
log_info "1. Scale cluster from ${CURRENT_INSTANCES} to $((CURRENT_INSTANCES - 1)) instances"
log_info "2. Wait for ${TARGET_POD} to terminate"
log_info "3. Clear pgdata on PVC ${TARGET_PVC} (PVC preserved)"
log_info "4. Run pg_basebackup from primary ${PRIMARY}"
log_info "5. Scale cluster back to ${CURRENT_INSTANCES} instances"
echo ""

read -p "Type 'yes' to proceed: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    log_info "Aborted."
    exit 0
fi

# === STEP 1: Scale down ===
log_info "Step 1/5: Scaling to $((CURRENT_INSTANCES - 1)) instances..."
kubectl patch cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" --type=merge \
    -p "{\"spec\":{\"instances\":$((CURRENT_INSTANCES - 1))}}"

# === STEP 2: Wait for pod termination ===
log_info "Step 2/5: Waiting for ${TARGET_POD} to terminate..."
TIMEOUT=120
ELAPSED=0
while kubectl get pod "${TARGET_POD}" -n "${NAMESPACE}" &>/dev/null; do
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        log_warn "Timeout. Force deleting pod..."
        kubectl delete pod "${TARGET_POD}" -n "${NAMESPACE}" --force --grace-period=0 || true
        sleep 5
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done
echo ""
log_info "Pod terminated."

# === STEP 3: Clear pgdata ===
log_info "Step 3/5: Clearing pgdata on PVC ${TARGET_PVC}..."
CLEANER_POD="${CLUSTER_NAME}-cleaner-${REPLICA_NUM}-$$"

kubectl run "${CLEANER_POD}" \
    --image=docker.io/library/alpine:latest \
    --restart=Never \
    -n "${NAMESPACE}" \
    --overrides="{
        \"spec\": {
            \"containers\": [{
                \"name\": \"cleaner\",
                \"image\": \"docker.io/library/alpine:latest\",
                \"command\": [\"sh\", \"-c\", \"echo Clearing pgdata... && rm -rf /pgdata/* && echo Done.\"],
                \"volumeMounts\": [{\"name\": \"pgdata\", \"mountPath\": \"/pgdata\"}]
            }],
            \"volumes\": [{
                \"name\": \"pgdata\",
                \"persistentVolumeClaim\": {\"claimName\": \"${TARGET_PVC}\"}
            }]
        }
    }"

sleep 10
kubectl logs "${CLEANER_POD}" -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete pod "${CLEANER_POD}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
log_info "pgdata cleared."

# === STEP 4: pg_basebackup ===
log_info "Step 4/5: Running pg_basebackup from ${PRIMARY}..."

PRIMARY_IP=$(kubectl get pod "${PRIMARY}" -n "${NAMESPACE}" -o jsonpath='{.status.podIP}')
REPLICATION_SECRET="${CLUSTER_NAME}-replication"

# Get postgres UID/GID from primary
POSTGRES_UID=$(kubectl exec "${PRIMARY}" -n "${NAMESPACE}" -c postgres -- id -u postgres 2>/dev/null || echo "26")
POSTGRES_GID=$(kubectl exec "${PRIMARY}" -n "${NAMESPACE}" -c postgres -- id -g postgres 2>/dev/null || echo "26")

log_info "Primary IP: ${PRIMARY_IP}"
log_info "Postgres UID/GID: ${POSTGRES_UID}/${POSTGRES_GID}"

BASEBACKUP_POD="${CLUSTER_NAME}-basebackup-${REPLICA_NUM}-$$"

kubectl run "${BASEBACKUP_POD}" \
    --image=ghcr.io/cloudnative-pg/postgresql:16 \
    --restart=Never \
    -n "${NAMESPACE}" \
    --overrides="{
        \"spec\": {
            \"securityContext\": {
                \"runAsUser\": ${POSTGRES_UID},
                \"runAsGroup\": ${POSTGRES_GID},
                \"fsGroup\": ${POSTGRES_GID}
            },
            \"containers\": [{
                \"name\": \"basebackup\",
                \"image\": \"ghcr.io/cloudnative-pg/postgresql:16\",
                \"command\": [\"sh\", \"-c\", \"mkdir -p /pgdata/pgdata && pg_basebackup -h ${PRIMARY_IP} -U streaming_replica -D /pgdata/pgdata -Fp -Xs -P -R && echo 'pg_basebackup complete'\"],
                \"env\": [{
                    \"name\": \"PGPASSWORD\",
                    \"valueFrom\": {\"secretKeyRef\": {\"name\": \"${REPLICATION_SECRET}\", \"key\": \"password\"}}
                }],
                \"volumeMounts\": [{\"name\": \"pgdata\", \"mountPath\": \"/pgdata\"}]
            }],
            \"volumes\": [{
                \"name\": \"pgdata\",
                \"persistentVolumeClaim\": {\"claimName\": \"${TARGET_PVC}\"}
            }]
        }
    }"

log_info "Waiting for pg_basebackup (this may take a while)..."
TIMEOUT=600
ELAPSED=0
while true; do
    STATUS=$(kubectl get pod "${BASEBACKUP_POD}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "${STATUS}" == "Succeeded" ]]; then
        log_info "pg_basebackup completed!"
        break
    elif [[ "${STATUS}" == "Failed" ]]; then
        log_error "pg_basebackup FAILED!"
        kubectl logs "${BASEBACKUP_POD}" -n "${NAMESPACE}" || true
        kubectl delete pod "${BASEBACKUP_POD}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
        log_error "Restoring cluster to ${CURRENT_INSTANCES} instances..."
        kubectl patch cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" --type=merge \
            -p "{\"spec\":{\"instances\":${CURRENT_INSTANCES}}}"
        exit 1
    elif [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        log_error "Timeout!"
        kubectl logs "${BASEBACKUP_POD}" -n "${NAMESPACE}" || true
        kubectl delete pod "${BASEBACKUP_POD}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true
        exit 1
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

kubectl logs "${BASEBACKUP_POD}" -n "${NAMESPACE}" 2>/dev/null || true
kubectl delete pod "${BASEBACKUP_POD}" -n "${NAMESPACE}" --force --grace-period=0 &>/dev/null || true

# === STEP 5: Scale back up ===
log_info "Step 5/5: Scaling back to ${CURRENT_INSTANCES} instances..."
kubectl patch cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" --type=merge \
    -p "{\"spec\":{\"instances\":${CURRENT_INSTANCES}}}"

log_info "Waiting for cluster to become healthy..."
TIMEOUT=300
ELAPSED=0
while true; do
    READY=$(kubectl get cluster "${CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyInstances}' 2>/dev/null || echo "0")
    if [[ "${READY}" == "${CURRENT_INSTANCES}" ]]; then
        log_info "Cluster healthy: ${READY}/${CURRENT_INSTANCES}"
        break
    elif [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        log_warn "Timeout. Current: ${READY}/${CURRENT_INSTANCES}"
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
