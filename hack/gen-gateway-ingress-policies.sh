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

# Fetch all HTTPRoutes
ROUTES_JSON=$(kubectl get httproutes.gateway.networking.k8s.io -A -o json)

# Build mapping: namespace → gateway-class → sorted unique ports
# jq outputs lines: NAMESPACE GATEWAY_NAME BACKEND_NS BACKEND_PORT
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
    backendPort: .port
  } |
  "\(.routeNs)\t\(.gwName)\t\(.backendNs)\t\(.backendPort)"
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

# Build: backendNs + gwClass → sorted unique ports
# Using associative arrays in awk
declare -A NS_GW_PORTS
while IFS=$'\t' read -r routeNs gwName backendNs backendPort; do
  gwClass=$(gateway_class "$gwName")
  [[ -z "$gwClass" ]] && continue
  key="${backendNs}|${gwClass}"
  existing="${NS_GW_PORTS[$key]:-}"
  if [[ -n "$existing" ]]; then
    NS_GW_PORTS[$key]="${existing} ${backendPort}"
  else
    NS_GW_PORTS[$key]="$backendPort"
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

  content="# DERIVED: ports from HTTPRoute backendRefs targeting this namespace.
# Inputs: kubectl get httproutes.gateway.networking.k8s.io -A -o json
# Key: (gateway parentRef -> {xylem|phloem|cell-membrane}) + backendRef.port
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
