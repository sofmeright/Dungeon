#!/usr/bin/env bash
# gen-gateway-ingress-policies.sh — Derive per-namespace gateway ingress
# AuthorizationPolicies from live HTTPRoute backendRefs.
#
# Source of truth: hack/gen-gateway-ingress-policies.sh in this repo.
# Update the script in-place; do not hand-edit generated files.
#
# Usage:
#   ./hack/gen-gateway-ingress-policies.sh --generate   # write policy files
#   ./hack/gen-gateway-ingress-policies.sh --check       # diff + nonzero on drift
#
# Requires: kubectl, jq, gawk
set -euo pipefail

OVERLAY_DIR="fluxcd/infrastructure/configs/overlays/production/istio-policies"

# Gateway name-pattern → (SA namespace, SA name, short label)
declare -A GW_SA_NS=(
  [xylem]="arylls-lookout"
  [phloem]="kokiri-forest"
  [cell-membrane]="hyrule-castle"
)
declare -A GW_SA_NAME=(
  [xylem]="xylem-gateway-istio"
  [phloem]="phloem-gateway-istio"
  [cell-membrane]="cell-membrane-gateway-istio"
)

# Map gateway parentRef name to our short label.
# Returns empty string (skip) for unrecognised names.
gateway_class() {
  local name="$1"
  case "$name" in
    xylem-gateway*)        echo "xylem" ;;
    phloem-gateway*)       echo "phloem" ;;
    cell-membrane-gateway*) echo "cell-membrane" ;;
    neko-gateway*)         echo "" ;;  # excluded
    *)                     echo "" ;;
  esac
}

usage() {
  echo "Usage: $0 {--generate|--check}" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage
MODE="$1"
[[ "$MODE" == "--generate" || "$MODE" == "--check" ]] || usage

# Fetch all HTTPRoutes and Services (for targetPort resolution)
# EndpointSlices are lazily fetched only if a named targetPort needs resolution.
ROUTES_JSON=$(kubectl get httproutes.gateway.networking.k8s.io -A -o json)
SERVICES_JSON=$(kubectl get services -A -o json)
ENDPOINTSLICES_JSON=""

# Build mapping: namespace → gateway-class → sorted unique ports
# jq outputs lines: NAMESPACE GATEWAY_NAME BACKEND_NS BACKEND_SVC BACKEND_PORT
PARSED=$(echo "$ROUTES_JSON" | jq -r '
  .items[] |
  .metadata.namespace as $routeNs |
  (.spec.parentRefs // [])[] as $parent |
  (.spec.rules // [])[] |
  (.backendRefs // [])[] |
  select(.port != null) |
  {
    routeNs: $routeNs,
    gwName: $parent.name,
    backendNs: (.namespace // $routeNs),
    backendSvc: .name,
    backendPort: .port
  } |
  "\(.routeNs)\t\(.gwName)\t\(.backendNs)\t\(.backendSvc)\t\(.backendPort)"
')

if [[ -z "$PARSED" ]]; then
  echo "ERROR: no HTTPRoute backendRefs found" >&2
  exit 1
fi

# Validate: fail hard if any backendRef has no port
BAD_PORTS=$(echo "$ROUTES_JSON" | jq -r '
  .items[] |
  .metadata.namespace as $routeNs |
  (.spec.rules // [])[] |
  (.backendRefs // [])[] |
  select(.port == null) |
  "\($routeNs)/\(.name // "unnamed")"
')
if [[ -n "$BAD_PORTS" ]]; then
  echo "ERROR: backendRefs with missing port (hard-fail):" >&2
  echo "$BAD_PORTS" >&2
  exit 1
fi

# Warn on cross-namespace backend refs
echo "$PARSED" | gawk -F'\t' '{
  if ($1 != $3) {
    printf "WARN: cross-namespace backendRef: route in %s → backend in %s (gateway %s, port %s)\n", $1, $3, $2, $4 > "/dev/stderr"
  }
}'

# Resolve a service port to its targetPort (what the pod actually listens on).
# Usage: resolve_target_port NAMESPACE SERVICE_NAME SERVICE_PORT
# Falls back to SERVICE_PORT if the service or port entry is not found.
resolve_target_port() {
  local ns="$1" svcName="$2" svcPort="$3"

  # Look up Service → find port entry → get targetPort
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
    # Service not found or no matching port — fall back to service port
    echo "$svcPort"
    return
  fi

  # If targetPort is numeric, use it directly
  if [[ "$tp" =~ ^[0-9]+$ ]]; then
    echo "$tp"
  else
    # targetPort is a named port (e.g. "http") — resolve via EndpointSlice
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
      echo "$resolved"
    else
      echo "WARN: could not resolve named port '$tp' for $ns/$svcName:$svcPort — falling back to $svcPort" >&2
      echo "$svcPort"
    fi
  fi
}

# Build: backendNs + gwClass → sorted unique targetPorts
declare -A NS_GW_PORTS
while IFS=$'\t' read -r routeNs gwName backendNs backendSvc backendPort; do
  gwClass=$(gateway_class "$gwName")
  [[ -z "$gwClass" ]] && continue

  # Resolve service port → pod targetPort
  targetPort=$(resolve_target_port "$backendNs" "$backendSvc" "$backendPort")
  if [[ "$targetPort" != "$backendPort" ]]; then
    echo "  RESOLVE  ${backendNs}/${backendSvc}:${backendPort} → targetPort ${targetPort}"
  fi

  key="${backendNs}|${gwClass}"
  existing="${NS_GW_PORTS[$key]:-}"
  if [[ -n "$existing" ]]; then
    NS_GW_PORTS[$key]="${existing} ${targetPort}"
  else
    NS_GW_PORTS[$key]="$targetPort"
  fi
done <<< "$PARSED"

# Generate files
GENERATED_FILES=()
TMPDIR_CHECK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CHECK"' EXIT

for key in $(printf '%s\n' "${!NS_GW_PORTS[@]}" | sort); do
  ns="${key%%|*}"
  gwClass="${key##*|}"
  rawPorts="${NS_GW_PORTS[$key]}"

  # Deduplicate and numeric-sort ports
  sortedPorts=$(echo "$rawPorts" | tr ' ' '\n' | sort -un | tr '\n' ' ')
  sortedPorts="${sortedPorts% }"  # trim trailing space

  # Build quoted port list for YAML
  portYaml=""
  for p in $sortedPorts; do
    if [[ -n "$portYaml" ]]; then
      portYaml="${portYaml}, \"${p}\""
    else
      portYaml="\"${p}\""
    fi
  done

  gwSaNs="${GW_SA_NS[$gwClass]}"
  gwSaName="${GW_SA_NAME[$gwClass]}"

  filePath="${OVERLAY_DIR}/${ns}/allow-gateway-ingress-${gwClass}.yaml"
  GENERATED_FILES+=("$filePath")

  content="# DERIVED: pod targetPorts from HTTPRoute backendRefs targeting this namespace.
# Inputs: HTTPRoutes → Services (targetPort resolution) → EndpointSlices (named port resolution)
# Key: (gateway parentRef -> {xylem|phloem|cell-membrane}) + resolved targetPort
# Regenerate; do not hand-edit.
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-gateway-ingress-${gwClass}
spec:
  selector:
    matchLabels:
      policy.prplanit.com/ingress: \"true\"
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - cluster.local/ns/${gwSaNs}/sa/${gwSaName}
      to:
        - operation:
            ports: [${portYaml}]
"

  if [[ "$MODE" == "--generate" ]]; then
    mkdir -p "$(dirname "$filePath")"
    echo -n "$content" > "$filePath"
    echo "WROTE  $filePath"
  else
    # --check mode: write to temp, diff against existing
    tmpFile="${TMPDIR_CHECK}/${ns}-${gwClass}.yaml"
    echo -n "$content" > "$tmpFile"
    if [[ -f "$filePath" ]]; then
      if ! diff -u "$filePath" "$tmpFile" > /dev/null 2>&1; then
        echo "DRIFT  $filePath"
        diff -u "$filePath" "$tmpFile" || true
      fi
    else
      echo "MISSING  $filePath"
    fi
  fi
done

# Detect stale files: existing allow-gateway-ingress-*.yaml not in generated set
if [[ "$MODE" == "--check" ]]; then
  HAS_DRIFT=false
  while IFS= read -r existing; do
    [[ -z "$existing" ]] && continue
    found=false
    for gen in "${GENERATED_FILES[@]}"; do
      if [[ "$existing" == "$gen" ]]; then
        found=true
        break
      fi
    done
    if ! $found; then
      echo "STALE  $existing"
      HAS_DRIFT=true
    fi
  done < <(find "$OVERLAY_DIR" -name 'allow-gateway-ingress-*.yaml' -type f | sort)

  # Check for any drift/missing
  for key in $(printf '%s\n' "${!NS_GW_PORTS[@]}" | sort); do
    ns="${key%%|*}"
    gwClass="${key##*|}"
    filePath="${OVERLAY_DIR}/${ns}/allow-gateway-ingress-${gwClass}.yaml"
    tmpFile="${TMPDIR_CHECK}/${ns}-${gwClass}.yaml"
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
    echo "OK: all gateway ingress policies are up to date."
    exit 0
  fi
fi

echo ""
echo "Done. Generated ${#GENERATED_FILES[@]} policy files."
echo "NOTE: You must manually update each namespace overlay kustomization.yaml to include the new files."
