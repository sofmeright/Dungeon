# Node Failure Incident: dungeon-chest-003 CRI-O Corruption

**Date:** November 4-5, 2025
**Duration:** 13 hours 42 minutes (23:53 UTC Nov 4 → 13:35 UTC Nov 5)
**Severity:** High (20 CPU cores, 115GB RAM offline)
**Status:** Resolved (Nov 5, 13:35 UTC)

## Executive Summary

Node dungeon-chest-003 experienced catastrophic system hang and CRI-O metadata corruption during observability stack scaling, resulting in 10+ hours of downtime. Root cause was resource exhaustion during simultaneous Loki and Prometheus replica scaling.

## Timeline

### Nov 4, 22:45 UTC - Trigger Event
Commit c22999b8 "Scale observability stack for high availability" deployed:
- Loki: gateway scaled 1→3 replicas, added 100Gi persistent volumes
- Prometheus: operator scaled 1→2 replicas, kube-state-metrics 1→2 replicas

### Nov 4, 23:50-23:56 UTC - Resource Exhaustion Cascade
- Cluster-wide container scheduling activity spike
- All 5 control plane nodes update CRI-O metadata (normal operations)
- dungeon-chest-003 under severe resource pressure
- Kernel warning: `srcu_invoke_callbacks hogged CPU for >10000us`
- Multiple file corruption events:
  - `/var/lib/containers/storage/overlay-containers/volatile-containers.json` - zeroed (317,520 bytes → all null bytes)
  - `/var/log/journal/.../system.journal` - corrupted/uncleanly shut down

### Nov 4, 23:56:08 UTC - System Hang
- Logs stop abruptly
- Node stops heartbeating to cluster (NotReady at 23:53)
- No OOM, kernel panic, or shutdown messages
- Complete system freeze

### Nov 4, 23:56 - Nov 5, 02:41 UTC - Silent Period
- **2 hours 45 minutes of complete silence**
- No journal entries whatsoever
- System completely hung/frozen
- Likely hardware watchdog timeout or hypervisor intervention pending

### Nov 5, 02:41 UTC - Hard Reset
- Kernel message: "Power-on or device reset occurred"
- System rebooted (ACPI/watchdog/hypervisor forced reset)
- CRI-O attempts to start, reads corrupt JSON file, crashes immediately
- Fatal error: `loading "/var/lib/containers/storage/overlay-containers/volatile-containers.json": []*storage.Container: decode slice: expect [ or n, but found \x00`
- CRI-O crash-looping: 160+ restarts
- Kubelet depends on CRI-O socket, crash-looping: 3,667+ restarts
- Node remains NotReady

### Nov 5, 13:30-13:35 UTC - Investigation & Recovery
- Forensic analysis completed
- Root cause identified: resource exhaustion → incomplete writes → corruption
- Recovery executed:
  - 13:34:53 UTC: Removed corrupt volatile-containers.json file
  - 13:34:53 UTC: Restarted CRI-O service (successful)
  - 13:34:58 UTC: Restarted kubelet service (successful)
  - 13:35:08 UTC: Node reports Ready status
  - Cluster capacity fully restored (all 10 nodes Ready)
  - Prometheus pods scheduling and running

## Technical Details

### Affected Node Specifications
- **Node:** dungeon-chest-003 (172.22.144.172)
- **Resources:** 20 CPU cores, 115GB RAM
- **Platform:** VM on Proxmox hypervisor
- **OS:** Ubuntu with Linux 6.8.0-87-generic
- **Kubernetes:** v1.34.1
- **Container Runtime:** CRI-O 1.34.0
- **Filesystem:** ext4 on LVM (/dev/mapper/ubuntu--vg-ubuntu--lv)

### Corruption Evidence

**File: `/var/lib/containers/storage/overlay-containers/volatile-containers.json`**
- Size: 317,520 bytes
- Content: All null bytes (0x00)
- Last Modified: Nov 4, 23:56:10 UTC
- Pattern: Complete file zeroing (typical of incomplete write during crash)

**Hexdump output:**
```
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
0004d850
```

**CRI-O error:**
```
level=fatal msg="validating root config: failed to get store to set defaults:
loading \"/var/lib/containers/storage/overlay-containers/volatile-containers.json\":
[]*storage.Container: decode slice: expect [ or n, but found \x00..."
```

### Cluster-Wide Impact Assessment

**Control plane nodes (intact):**
- map-001: 43KB, modified Nov 4 23:56:10 (valid JSON)
- map-002: 40KB, modified Nov 4 23:55:39 (valid JSON)
- map-003: 37KB, modified Nov 4 23:56:11 (valid JSON)
- map-004: 49KB, modified Nov 4 23:56:28 (valid JSON)
- map-005: 38KB, modified Nov 4 23:56:16 (valid JSON)

**Worker nodes (healthy):**
- chest-001: 320KB, active
- chest-002: 349KB, active
- chest-004: 234KB, active
- chest-005: 313KB, active

**Observation:** All nodes had CRI-O activity at the same time (23:55-23:56), but only dungeon-chest-003 suffered corruption. This indicates the node was already under extreme resource pressure that prevented proper file writes.

### Evidence NOT Found
- ❌ OOM killer activity
- ❌ Kernel panic
- ❌ Filesystem errors (ext4 reported "clean")
- ❌ Disk failures (no I/O errors in dmesg)
- ❌ Graceful shutdown messages
- ❌ Emergency/panic mode triggers

## Root Cause Analysis

### Primary Cause
**Resource exhaustion during observability stack scaling:**

1. **Trigger:** Simultaneous scaling of multiple observability components:
   - Loki gateway: 1→3 replicas (3x the pods)
   - Loki persistent volumes: 0→300Gi total (new storage demands)
   - Prometheus operator: 1→2 replicas
   - Kube-state-metrics: 1→2 replicas

2. **Resource Cascade:**
   - New pods scheduled across cluster
   - dungeon-chest-003 already heavily loaded
   - Insufficient memory/CPU for new workload
   - System began thrashing (high CPU usage, memory pressure)

3. **System Failure:**
   - File writes in progress became incomplete
   - CRI-O metadata file partially written, then system froze
   - Incomplete writes resulted in null-byte filled file
   - System became completely unresponsive

4. **Hard Reset:**
   - After ~2.75 hours, watchdog/hypervisor forced hard reset
   - "Power-on or device reset occurred" message confirms non-graceful reboot

5. **Recovery Failure:**
   - CRI-O attempted to read corrupt metadata on boot
   - JSON parser failed on null bytes
   - Service crash-loop prevented container runtime startup
   - Kubelet depends on CRI-O socket, also crash-looped
   - Node stuck in NotReady state

### Contributing Factors
- No Pod Disruption Budgets to limit simultaneous scaling
- No kubelet resource reservation to protect system daemons
- No eviction thresholds to prevent complete resource exhaustion
- CRI-O volatile metadata is a single point of failure
- Insufficient resource capacity for observability stack growth

## Impact Assessment

### Service Impact
- **Duration:** 10+ hours of reduced cluster capacity
- **Lost Resources:** 20 CPU cores, 115GB RAM unavailable
- **Affected Workloads:** Pods pending due to insufficient resources
  - Prometheus pods: 0/3 replicas running (stuck in Pending)
  - Other workloads unable to schedule on remaining nodes

### Data Impact
- ✅ No data loss (all PVCs intact, backed by Ceph RBD)
- ✅ Prometheus TSDB data preserved
- ✅ Loki data in S3 backend preserved
- ⚠️ CRI-O container metadata lost (recreatable)
- ⚠️ System journal corrupted (logs lost for crash period)

## Resolution

### Immediate Recovery Steps
1. Remove corrupt CRI-O metadata file:
   ```bash
   ssh dungeon-chest-003 "sudo rm /var/lib/containers/storage/overlay-containers/volatile-containers.json"
   ```

2. Restart CRI-O service:
   ```bash
   ssh dungeon-chest-003 "sudo systemctl restart crio"
   ```

3. Restart kubelet service:
   ```bash
   ssh dungeon-chest-003 "sudo systemctl restart kubelet"
   ```

4. Verify node recovery:
   ```bash
   kubectl get node dungeon-chest-003
   ```

### File Recovery Details
The `volatile-containers.json` file is **ephemeral metadata** that CRI-O uses to track running containers. When removed:
- CRI-O regenerates it on startup
- Running containers are reconciled from actual storage state
- Kubernetes reconciles pod state automatically
- No persistent data is lost

## Prevention & Mitigation

### Immediate Actions (High Priority)

1. **Implement Resource Reservations**
   - Configure kubelet `--system-reserved` for CRI-O, kubelet, and system daemons
   - Set `--eviction-hard` thresholds to prevent complete exhaustion
   - Reserve minimum CPU/memory on each node for system stability

2. **Add Pod Disruption Budgets**
   - Limit simultaneous pod evictions during scaling
   - Ensure gradual rollout of replica increases
   - Prevent resource stampedes

3. **CRI-O Metadata Resilience**
   - Implement automated corruption detection
   - Create recovery automation: detect corrupt file → remove → restart CRI-O
   - Add monitoring/alerting for CRI-O crash-loops

### Medium-Term Improvements

4. **Node Health Monitoring**
   - Alert on node conditions: MemoryPressure, DiskPressure, PIDPressure
   - Monitor CRI-O service health across all nodes
   - Alert on kubelet crash-loops

5. **Observability Stack Resource Planning**
   - Right-size resource requests/limits for Loki, Prometheus
   - Use node affinity to spread observability pods
   - Implement horizontal pod autoscaling with conservative limits

6. **Gradual Scaling Procedures**
   - Never scale multiple observability components simultaneously
   - Use rolling updates with delays between replicas
   - Validate cluster capacity before scaling operations

### Long-Term Considerations

7. **Cluster Capacity Management**
   - Add cluster autoscaling (if running on elastic infrastructure)
   - Implement resource quotas per namespace
   - Regular capacity planning reviews

8. **Testing & Validation**
   - Chaos engineering: test node failures in controlled manner
   - Validate recovery procedures regularly
   - Document runbooks for common failure scenarios

## Lessons Learned

### What Went Well
- ✅ Ceph RBD storage remained intact (no data loss)
- ✅ Control plane remained operational (cluster API available)
- ✅ Forensic investigation revealed clear root cause
- ✅ Recovery procedure is straightforward (remove file, restart)

### What Went Wrong
- ❌ No resource pressure alerting before failure
- ❌ Simultaneous scaling caused resource stampede
- ❌ No protection against complete node resource exhaustion
- ❌ CRI-O metadata corruption took node offline for 10+ hours
- ❌ No automated recovery for this failure mode

### Key Takeaways

1. **Observability is critical infrastructure** - treat scaling with same care as production services
2. **Resource exhaustion can cause file corruption** - even on clean filesystems
3. **CRI-O volatile metadata is a single point of failure** - requires resilience measures
4. **Gradual scaling prevents cascading failures** - never rush large infrastructure changes
5. **Automation is essential** - manual intervention delayed recovery by hours

## Related Incidents
- None (first occurrence of this failure pattern)

## References
- Commit: c22999b8 "Scale observability stack for high availability"
- Node: dungeon-chest-003 (172.22.144.172)
- Kubernetes Issue: CRI-O metadata corruption during resource exhaustion
- Similar patterns: https://github.com/cri-o/cri-o/issues?q=volatile-containers

## Incident Responders
- SoFMeRight (forensic analysis and recovery)

## Follow-Up Actions
- [ ] Implement kubelet resource reservations on all nodes
- [ ] Add Pod Disruption Budgets for observability stack
- [ ] Create automated CRI-O corruption recovery
- [ ] Add node resource pressure alerting
- [ ] Document observability scaling procedures
- [ ] Review and right-size Loki/Prometheus resource requests
