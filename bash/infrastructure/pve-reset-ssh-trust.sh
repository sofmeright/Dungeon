#!/usr/bin/env bash
# pve-reset-ssh-trust.sh — Full SSH host key trust reset for a Proxmox cluster.
# Run on ONE node. Requires pmxcfs mounted at /etc/pve.
# Resets trust on THIS node AND populates the shared pmxcfs files for all nodes.
set -euo pipefail

# Node names as PVE knows them (capitalized = directory names under /etc/pve/nodes/)
NODES=(Avocado Bamboo Cosmos Dragonfruit Eggplant)

# Mapping: capitalized name → lowercase hostname → IP
declare -A NODE_IP
NODE_IP[Avocado]=172.22.22.3
NODE_IP[Bamboo]=172.22.22.4
NODE_IP[Cosmos]=172.22.22.5
NODE_IP[Dragonfruit]=172.22.22.6
NODE_IP[Eggplant]=172.22.22.7

THIS_NODE=$(hostname -s)

if [[ ! -d /etc/pve/nodes ]]; then
  echo "ERROR: /etc/pve/nodes not found — is this a Proxmox node with pmxcfs mounted?" >&2
  exit 1
fi

echo "=== Running on: $THIS_NODE ==="
echo ""

# --- Step 1: Clear all known_hosts everywhere ---
echo "=== Step 1: Clearing all known_hosts ==="

for node in "${NODES[@]}"; do
  f="/etc/pve/nodes/$node/ssh_known_hosts"
  if [[ -f "$f" ]]; then
    > "$f"
    echo "  cleared $f"
  fi
done

if [[ -f /etc/pve/priv/known_hosts ]]; then
  > /etc/pve/priv/known_hosts
  echo "  cleared /etc/pve/priv/known_hosts"
fi

> /root/.ssh/known_hosts
echo "  cleared /root/.ssh/known_hosts"

if [[ -f /etc/ssh/ssh_known_hosts ]]; then
  > /etc/ssh/ssh_known_hosts
  echo "  cleared /etc/ssh/ssh_known_hosts"
fi

echo ""

# --- Step 2: Scan fresh host keys from every node ---
# PVE uses unhashed entries with capitalized names, lowercase names, and IPs.
echo "=== Step 2: Scanning host keys from all nodes ==="

TMPKEYS=$(mktemp)
trap 'rm -f "$TMPKEYS"' EXIT

for node in "${NODES[@]}"; do
  lower=$(echo "$node" | tr '[:upper:]' '[:lower:]')
  ip="${NODE_IP[$node]}"

  echo "  scanning $node ($lower / $ip)..."

  # Scan by all name variants — unhashed (no -H) so PVE can match
  for target in "$lower" "$node" "$ip"; do
    if keys=$(ssh-keyscan -t ed25519 "$target" 2>/dev/null); then
      echo "$keys" >> "$TMPKEYS"
    else
      echo "    WARN: could not scan $target" >&2
    fi
  done

  # Also add aliased entries: "name,ip" format that SSH/PVE understands
  if keys=$(ssh-keyscan -t ed25519 "$lower" 2>/dev/null); then
    echo "$keys" | while IFS= read -r line; do
      [[ "$line" == \#* ]] && continue
      [[ -z "$line" ]] && continue
      keytype=$(echo "$line" | awk '{print $2}')
      keydata=$(echo "$line" | awk '{print $3}')
      echo "$node,$lower,$ip $keytype $keydata" >> "$TMPKEYS"
    done
  fi
done

echo ""

# --- Step 3: Populate all known_hosts locations ---
echo "=== Step 3: Populating known_hosts files ==="

# /etc/pve/priv/known_hosts — cluster-wide, used by PVE tools
cp "$TMPKEYS" /etc/pve/priv/known_hosts
echo "  wrote /etc/pve/priv/known_hosts ($(wc -l < /etc/pve/priv/known_hosts) lines)"

# Per-node ssh_known_hosts — PVE reads these for inter-node ops
for node in "${NODES[@]}"; do
  f="/etc/pve/nodes/$node/ssh_known_hosts"
  if [[ -f "$f" ]] || [[ -d "/etc/pve/nodes/$node" ]]; then
    cp "$TMPKEYS" "$f"
    echo "  wrote $f ($(wc -l < "$f") lines)"
  fi
done

# /root/.ssh/known_hosts — standard SSH client
cp "$TMPKEYS" /root/.ssh/known_hosts
echo "  wrote /root/.ssh/known_hosts ($(wc -l < /root/.ssh/known_hosts) lines)"

echo ""

# --- Step 4: Verify SSH connectivity ---
echo "=== Step 4: Verifying SSH to each node ==="
for node in "${NODES[@]}"; do
  lower=$(echo "$node" | tr '[:upper:]' '[:lower:]')
  ip="${NODE_IP[$node]}"

  # Test by hostname
  if result=$(ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=5 "$lower" hostname 2>/dev/null); then
    echo "  OK  $lower → $result"
  else
    echo "  FAIL $lower (by hostname)" >&2
  fi

  # Test by IP
  if result=$(ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=5 "$ip" hostname 2>/dev/null); then
    echo "  OK  $ip → $result"
  else
    echo "  FAIL $ip (by IP)" >&2
  fi
done

echo ""

# --- Step 5: Clear known_hosts on remote nodes and push fresh keys ---
echo "=== Step 5: Resetting known_hosts on remote nodes ==="
for node in "${NODES[@]}"; do
  lower=$(echo "$node" | tr '[:upper:]' '[:lower:]')
  [[ "$lower" == "$(echo "$THIS_NODE" | tr '[:upper:]' '[:lower:]')" ]] && continue

  echo "  resetting $lower..."
  if ssh -o StrictHostKeyChecking=yes -o ConnectTimeout=5 "$lower" bash -s <<'REMOTE' 2>/dev/null; then
    # Remote node: clear local known_hosts (pmxcfs files are already updated via shared filesystem)
    > /root/.ssh/known_hosts
    # Copy from the shared pmxcfs (already populated by the initiating node)
    if [[ -f /etc/pve/priv/known_hosts ]]; then
      cp /etc/pve/priv/known_hosts /root/.ssh/known_hosts
    fi
    echo "    done"
REMOTE
    echo "    OK $lower"
  else
    echo "    WARN: could not reset $lower — do it manually:" >&2
    echo "      ssh root@$lower 'cp /etc/pve/priv/known_hosts /root/.ssh/known_hosts'" >&2
  fi
done

echo ""

# --- Step 6: Restart PVE services ---
echo "=== Step 6: Restarting PVE services ==="
for svc in pve-cluster pvedaemon pveproxy; do
  if systemctl is-active "$svc" &>/dev/null || systemctl is-enabled "$svc" &>/dev/null; then
    systemctl restart "$svc" && echo "  restarted $svc" || echo "  WARN: failed to restart $svc" >&2
  else
    echo "  skip $svc (not found)"
  fi
done

echo ""
echo "=== Done ==="
echo "If any remote nodes showed WARN above, SSH to them and run:"
echo "  cp /etc/pve/priv/known_hosts /root/.ssh/known_hosts"
