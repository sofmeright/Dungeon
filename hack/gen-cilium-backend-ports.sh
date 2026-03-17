#!/usr/bin/env bash
# gen-cilium-backend-ports.sh — Derive Cilium CCNP port stanzas from live
# cluster state (HTTPRoutes, Services, EndpointSlices, Gatus annotations).
#
# Source of truth: hack/gen-cilium-backend-ports.sh in this repo.
# Update the script in-place; do not hand-edit generated files.
#
# Generated files:
#   fluxcd/infrastructure/configs/base/cilium-policies/ccnp-contract-ingress-backend.yaml
#   fluxcd/infrastructure/configs/base/cilium-policies/ccnp-allow-gatus-healthcheck.yaml
#
# Usage:
#   ./hack/gen-cilium-backend-ports.sh --generate   # write policy files
#   ./hack/gen-cilium-backend-ports.sh --check       # diff + nonzero on drift
#
# Requires: kubectl, jq
set -euo pipefail

BASE_DIR="fluxcd/infrastructure/configs/base/cilium-policies"

usage() {
  echo "Usage: $0 {--generate|--check}" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage
MODE="$1"
[[ "$MODE" == "--generate" || "$MODE" == "--check" ]] || usage

# --- Shared cluster data (fetched once) ---
SERVICES_JSON=$(kubectl get services -A -o json)
ENDPOINTSLICES_JSON=""

# Resolve a service port to its numeric targetPort (pod containerPort).
# Usage: resolve_target_port NAMESPACE SERVICE_NAME SERVICE_PORT
# Falls back to SERVICE_PORT if the service or port entry is not found.
resolve_target_port() {
  local ns="$1" svcName="$2" svcPort="$3"

  local tp
  tp=$(echo "$SERVICES_JSON" | jq -r \
    --arg ns "$ns" --arg name "$svcName" --argjson port "$svcPort" '
    .items[] |
    select(.metadata.namespace == $ns and .metadata.name == $name) |
    (.spec.ports // [])[] |
    select(.port == $port) |
    .targetPort // .port
  ' 2>/dev/null | head -1)

  if [[ -z "$tp" ]]; then
    echo "$svcPort"
    return
  fi

  if [[ "$tp" =~ ^[0-9]+$ ]]; then
    if [[ "$tp" != "$svcPort" ]]; then
      echo "  RESOLVE  ${ns}/${svcName}:${svcPort} → targetPort ${tp}" >&2
    fi
    echo "$tp"
  else
    # Named port — resolve via EndpointSlice
    if [[ -z "${ENDPOINTSLICES_JSON:-}" ]]; then
      ENDPOINTSLICES_JSON=$(kubectl get endpointslices -A -o json)
    fi
    local resolved
    resolved=$(echo "$ENDPOINTSLICES_JSON" | jq -r \
      --arg ns "$ns" --arg svc "$svcName" --arg pname "$tp" '
      .items[] |
      select(.metadata.namespace == $ns) |
      select(.metadata.labels["kubernetes.io/service-name"] == $svc) |
      (.ports // [])[] |
      select(.name == $pname) |
      .port
    ' 2>/dev/null | head -1)

    if [[ -n "$resolved" && "$resolved" =~ ^[0-9]+$ ]]; then
      if [[ "$resolved" != "$svcPort" ]]; then
        echo "  RESOLVE  ${ns}/${svcName}:${svcPort} → named '${tp}' → ${resolved}" >&2
      fi
      echo "$resolved"
    else
      echo "WARN: could not resolve named port '${tp}' for ${ns}/${svcName}:${svcPort}" >&2
      echo "$svcPort"
    fi
  fi
}

# --- Ingress-backend: resolve HTTPRoute backend targetPorts ---
resolve_ingress_backend_ports() {
  local ROUTES_JSON
  ROUTES_JSON=$(kubectl get httproutes.gateway.networking.k8s.io -A -o json)

  local PARSED
  PARSED=$(echo "$ROUTES_JSON" | jq -r '
    .items[] |
    .metadata.namespace as $routeNs |
    (.spec.parentRefs // [])[] as $parent |
    (.spec.rules // [])[] |
    (.backendRefs // [])[] |
    select(.port != null) |
    "\($routeNs)\t\($parent.name)\t\(.namespace // $routeNs)\t\(.name)\t\(.port)"
  ')

  if [[ -z "$PARSED" ]]; then
    echo "ERROR: no HTTPRoute backendRefs found" >&2
    exit 1
  fi

  local PORTS=()
  while IFS=$'\t' read -r routeNs gwName backendNs backendSvc backendPort; do
    case "$gwName" in
      xylem-gateway*|phloem-gateway*|cell-membrane-gateway*) ;;
      *) continue ;;
    esac
    local targetPort
    targetPort=$(resolve_target_port "$backendNs" "$backendSvc" "$backendPort")
    PORTS+=("$targetPort")
  done <<< "$PARSED"

  printf '%s\n' "${PORTS[@]}" | sort -un
}

# --- Gatus probes: resolve annotated service targetPorts + probe-labelled pod containerPorts ---
resolve_gatus_probe_ports() {
  local ALL_PORTS=()

  # Source 1: Gatus-annotated services — resolve each service port to targetPort
  local ANNOTATED_SVCS
  ANNOTATED_SVCS=$(echo "$SERVICES_JSON" | jq -r '
    .items[] |
    select(.metadata.annotations["gatus.home-operations.com/enabled"] == "true"
           or .metadata.annotations["gatus.home-operations.com/endpoint"] != null) |
    .metadata.namespace as $ns | .metadata.name as $name |
    (.spec.ports // [])[] |
    "\($ns)\t\($name)\t\(.port)"
  ')

  if [[ -n "$ANNOTATED_SVCS" ]]; then
    while IFS=$'\t' read -r ns svcName port; do
      [[ -z "$port" ]] && continue
      local tp
      tp=$(resolve_target_port "$ns" "$svcName" "$port")
      ALL_PORTS+=("$tp")
    done <<< "$ANNOTATED_SVCS"
  fi

  # Source 2: Probe-labelled pod containerPorts (direct ground truth)
  local PROBE_PORTS
  PROBE_PORTS=$(kubectl get pods -A -l policy.prplanit.com/probe=true -o json | jq -r '
    .items[] |
    (.spec.containers // [])[] |
    (.ports // [])[] |
    select(.protocol == "TCP" or .protocol == null) |
    .containerPort
  ')

  if [[ -n "$PROBE_PORTS" ]]; then
    while read -r port; do
      [[ -z "$port" ]] && continue
      ALL_PORTS+=("$port")
    done <<< "$PROBE_PORTS"
  fi

  printf '%s\n' "${ALL_PORTS[@]}" | sort -un
}

# --- Build YAML port stanza from sorted port list ---
# Cilium enforces max 40 ports per toPorts entry. This function chunks
# the port list and emits multiple toPorts entries if needed.
# Args: indent prefix_indent
#   indent       = indentation for port items (e.g., "            ")
#   prefix_indent = indentation for "- ports:" lines (e.g., "        ")
# When only one chunk exists, emits a flat port list (no toPorts wrapper).
# When multiple chunks exist, emits multiple "- ports:" blocks.
MAX_PORTS_PER_TOPORTS=40

build_port_yaml() {
  local indent="$1"
  local prefix_indent="$2"
  local ports=()
  while read -r port; do
    [[ -z "$port" ]] && continue
    ports+=("$port")
  done

  local total=${#ports[@]}
  local chunk_start=0
  local chunk_idx=0

  while [[ $chunk_start -lt $total ]]; do
    if [[ $chunk_idx -gt 0 ]]; then
      # Additional toPorts entry — need the "- ports:" wrapper
      printf '%s- ports:\n' "$prefix_indent"
    fi
    local chunk_end=$((chunk_start + MAX_PORTS_PER_TOPORTS))
    [[ $chunk_end -gt $total ]] && chunk_end=$total
    for ((i=chunk_start; i<chunk_end; i++)); do
      printf '%s- port: "%s"\n' "$indent" "${ports[$i]}"
      printf '%s  protocol: TCP\n' "$indent"
    done
    chunk_start=$chunk_end
    chunk_idx=$((chunk_idx + 1))
  done
}

# --- Generate complete CCNP files ---
GENERATED_FILES=()
TMPDIR_CHECK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CHECK"' EXIT

emit_file() {
  local filePath="$1" content="$2"
  GENERATED_FILES+=("$filePath")

  if [[ "$MODE" == "--generate" ]]; then
    mkdir -p "$(dirname "$filePath")"
    printf '%s' "$content" > "$filePath"
    echo "WROTE  $filePath"
  else
    local tmpFile="${TMPDIR_CHECK}/$(basename "$filePath")"
    printf '%s' "$content" > "$tmpFile"
    if [[ -f "$filePath" ]]; then
      if ! diff -u "$filePath" "$tmpFile" > /dev/null 2>&1; then
        echo "DRIFT  $filePath"
        diff -u "$filePath" "$tmpFile" || true
      fi
    else
      echo "MISSING  $filePath"
    fi
  fi
}

# --- File 1: ccnp-contract-ingress-backend.yaml ---
echo "Resolving ingress-backend targetPorts..." >&2
INGRESS_PORTS=$(resolve_ingress_backend_ports)
INGRESS_PORT_YAML=$(echo "$INGRESS_PORTS" | build_port_yaml "            " "        ")

emit_file "${BASE_DIR}/ccnp-contract-ingress-backend.yaml" \
"# DERIVED: resolved pod targetPorts from HTTPRoute backendRefs.
# Inputs: HTTPRoutes → Services (targetPort resolution) → EndpointSlices (named port resolution)
# Source of truth: hack/gen-cilium-backend-ports.sh
# Regenerate; do not hand-edit.
apiVersion: \"cilium.io/v2\"
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: contract-ingress-backend
spec:
  description: >-
    Contract: ingress gateway pods may reach backend application pods.
    Source is restricted to the 3 gateway namespaces (arylls-lookout,
    kokiri-forest, hyrule-castle) AND must carry the ingress-gateway
    client-class label. Destination pods must carry
    policy.prplanit.com/ingress: \"true\".
  enableDefaultDeny:
    egress: false
    ingress: false
  endpointSelector:
    matchLabels:
      policy.prplanit.com/ingress: \"true\"
  ingress:
    - fromEndpoints:
        # xylem-gateway (internal *.pcfae.com)
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: arylls-lookout
            policy.prplanit.com/client-class: ingress-gateway
        # phloem-gateway (personal *.sofmeright.com, *.arbitorium.com, etc.)
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kokiri-forest
            policy.prplanit.com/client-class: ingress-gateway
        # cell-membrane-gateway (business *.prplanit.com, *.precisionplanit.com, etc.)
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: hyrule-castle
            policy.prplanit.com/client-class: ingress-gateway
      toPorts:
        - ports:
${INGRESS_PORT_YAML}
"

# --- File 2: ccnp-allow-gatus-healthcheck.yaml ---
echo "Resolving gatus probe targetPorts..." >&2
GATUS_PORTS=$(resolve_gatus_probe_ports)
GATUS_PORT_YAML=$(echo "$GATUS_PORTS" | build_port_yaml "            " "        ")

emit_file "${BASE_DIR}/ccnp-allow-gatus-healthcheck.yaml" \
"# DERIVED: resolved pod targetPorts from Gatus-annotated services and probe-labelled pods.
# Inputs: Gatus annotations → Services (targetPort resolution) → probe-labelled pod containerPorts
# Source of truth: hack/gen-cilium-backend-ports.sh
# Regenerate; do not hand-edit.
apiVersion: \"cilium.io/v2\"
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: allow-gatus-healthcheck
spec:
  description: >-
    Allows Gatus health checker to reach probe-labelled endpoints.
    Gatus runs in gossip-stone namespace and probes service health
    across the cluster on application and infrastructure ports.
  enableDefaultDeny:
    egress: false
    ingress: false
  endpointSelector:
    matchLabels:
      policy.prplanit.com/probe: \"true\"
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: gossip-stone
            app.kubernetes.io/name: gatus
      toPorts:
        - ports:
${GATUS_PORT_YAML}
"

# --- Drift detection (--check mode) ---
if [[ "$MODE" == "--check" ]]; then
  HAS_DRIFT=false
  for filePath in "${GENERATED_FILES[@]}"; do
    tmpFile="${TMPDIR_CHECK}/$(basename "$filePath")"
    if [[ ! -f "$filePath" ]]; then
      HAS_DRIFT=true
    elif ! diff -q "$filePath" "$tmpFile" > /dev/null 2>&1; then
      HAS_DRIFT=true
    fi
  done

  if $HAS_DRIFT; then
    echo ""
    echo "FAIL: drift detected. Run --generate to update."
    exit 1
  else
    echo "OK: all Cilium backend-port policies are up to date."
    exit 0
  fi
fi

echo ""
echo "Done. Generated ${#GENERATED_FILES[@]} policy files."
