#!/usr/bin/env bash
# pve-ssh-trust-diag.sh — Diagnose SSH trust state on a Proxmox cluster node.
# Run on EACH node that has issues. Copy the full output and share it.
set -euo pipefail

NODES_LOWER=(avocado bamboo cosmos dragonfruit eggplant)
THIS_NODE=$(hostname -s | tr '[:upper:]' '[:lower:]')

echo "########## PVE SSH TRUST DIAGNOSTIC — $(hostname) ##########"
echo "date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "this_node: $THIS_NODE"
echo ""

# 1. Local host key fingerprints (what this node presents to others)
echo "===== LOCAL HOST KEY FINGERPRINTS ====="
for f in /etc/ssh/ssh_host_*_key.pub; do
  [[ -f "$f" ]] && ssh-keygen -lf "$f" 2>&1 && echo "  file: $f"
done
echo ""

# 2. SSH config — GlobalKnownHostsFile and UserKnownHostsFile
echo "===== SSHD CONFIG (HostKey lines) ====="
grep -n '^HostKey\|^#HostKey' /etc/ssh/sshd_config 2>/dev/null || echo "  (none found)"
echo ""

echo "===== SSH CLIENT CONFIG (known_hosts paths) ====="
ssh -G localhost 2>/dev/null | grep -i 'knownhostsfile\|globalknownhostsfile' || echo "  (could not query)"
echo ""

# 3. All known_hosts files and their contents
echo "===== KNOWN_HOSTS FILES ====="

echo "--- /root/.ssh/known_hosts ---"
if [[ -f /root/.ssh/known_hosts ]]; then
  wc -l < /root/.ssh/known_hosts | xargs -I{} echo "  lines: {}"
  cat /root/.ssh/known_hosts
else
  echo "  (does not exist)"
fi
echo ""

echo "--- /etc/ssh/ssh_known_hosts ---"
if [[ -f /etc/ssh/ssh_known_hosts ]]; then
  wc -l < /etc/ssh/ssh_known_hosts | xargs -I{} echo "  lines: {}"
  cat /etc/ssh/ssh_known_hosts
else
  echo "  (does not exist)"
fi
echo ""

echo "--- /etc/pve/priv/known_hosts ---"
if [[ -f /etc/pve/priv/known_hosts ]]; then
  wc -l < /etc/pve/priv/known_hosts | xargs -I{} echo "  lines: {}"
  cat /etc/pve/priv/known_hosts
else
  echo "  (does not exist)"
fi
echo ""

for node in "${NODES_LOWER[@]}"; do
  f="/etc/pve/nodes/${node^}/ssh_known_hosts"
  echo "--- $f ---"
  if [[ -f "$f" ]]; then
    wc -l < "$f" | xargs -I{} echo "  lines: {}"
    cat "$f"
  else
    echo "  (does not exist)"
  fi
  echo ""
done
echo ""

# 4. /etc/pve/priv/authorized_keys (cluster auth)
echo "===== /etc/pve/priv/authorized_keys ====="
if [[ -f /etc/pve/priv/authorized_keys ]]; then
  wc -l < /etc/pve/priv/authorized_keys | xargs -I{} echo "  lines: {}"
  while IFS= read -r line; do
    echo "  $(echo "$line" | ssh-keygen -lf - 2>/dev/null || echo "UNPARSEABLE: ${line:0:80}...")"
  done < /etc/pve/priv/authorized_keys
else
  echo "  (does not exist)"
fi
echo ""

# 5. /root/.ssh/authorized_keys
echo "===== /root/.ssh/authorized_keys ====="
if [[ -f /root/.ssh/authorized_keys ]]; then
  wc -l < /root/.ssh/authorized_keys | xargs -I{} echo "  lines: {}"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    echo "  $(echo "$line" | ssh-keygen -lf - 2>/dev/null || echo "UNPARSEABLE: ${line:0:80}...")"
  done < /root/.ssh/authorized_keys
else
  echo "  (does not exist)"
fi
echo ""

# 6. Remote key scan vs known_hosts comparison
echo "===== REMOTE KEY SCAN (live fingerprints from each node) ====="
for node in "${NODES_LOWER[@]}"; do
  echo "--- $node ---"
  if keys=$(ssh-keyscan "$node" 2>/dev/null); then
    echo "$keys" | while IFS= read -r line; do
      fp=$(echo "$line" | ssh-keygen -lf - 2>/dev/null) && echo "  $fp" || echo "  RAW: $line"
    done
  else
    echo "  UNREACHABLE"
  fi
done
echo ""

# 7. Actual SSH connection tests with verbose output
echo "===== SSH CONNECTION TESTS (verbose) ====="
for node in "${NODES_LOWER[@]}"; do
  [[ "$node" == "$THIS_NODE" ]] && continue
  echo "--- ssh $node ---"
  ssh -vvv -o BatchMode=yes -o ConnectTimeout=5 "$node" hostname 2>&1 | \
    grep -E 'Connecting to|Host key |REMOTE HOST|host_key:|debug1: (Host |Offering|Server host key|Will attempt|Authenticat|key_verify)|Warning:|match:|verification failed|Connection' || true
  echo "  exit_code: ${PIPESTATUS[0]}"
  echo ""
done

echo "########## END DIAGNOSTIC ##########"
