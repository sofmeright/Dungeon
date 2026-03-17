#!/usr/bin/env bash
# pre-commit-policy-guard.sh — Detect likely stale generated network/security policy.
#
# Called by pre-commit when staged changes touch files that can affect
# derived policy (HTTPRoutes, Services, Gatus annotations, generator scripts,
# generated policy files). Uses --check mode only — never auto-regenerates.
#
# Override: SKIP_GENERATED_POLICY_GUARD=1 git commit ...
set -euo pipefail

if [ "${SKIP_GENERATED_POLICY_GUARD:-}" = "1" ]; then
  exit 0
fi

# Cluster availability — checked once
CLUSTER_OK=false
if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null 2>&1; then
  CLUSTER_OK=true
fi

STALE_GENERATORS=()

for gen in hack/gen-cilium-backend-ports.sh hack/gen-gateway-ingress-policies.sh; do
  [ -x "$gen" ] || continue
  if $CLUSTER_OK; then
    if ! "$gen" --check &>/dev/null; then
      STALE_GENERATORS+=("  ./$gen --generate")
    fi
  else
    STALE_GENERATORS+=("  ./$gen --generate  (cluster unreachable, cannot verify)")
  fi
done

if [ ${#STALE_GENERATORS[@]} -gt 0 ]; then
  echo ""
  echo "Generated policy may be stale due to staged changes."
  echo ""
  echo "Affected generators:"
  for g in "${STALE_GENERATORS[@]}"; do
    echo "$g"
  done
  echo ""
  echo "Why this was blocked:"
  echo "  Changes were detected in files that can affect derived network/security"
  echo "  policy. Generated policy is not updated automatically because that would"
  echo "  implicitly bless security-surface changes."
  echo ""
  echo "Next step:"
  echo "  Run the generator(s), review the diff, stage intended changes, and commit again."
  echo ""
  echo "Override:"
  echo "  SKIP_GENERATED_POLICY_GUARD=1 git commit ..."
  echo ""
  exit 1
fi
