# Proxmox CPU Configuration for Kubernetes VMs

## Physical Hardware Summary

### Xeon Hosts (Avocado, Bamboo, Cosmos, Eggplant)
- **CPU**: 2× Intel Xeon E5-2618L v4
- **Total Resources**: 20 cores / 40 threads per host
- **Base Clock**: 2.20 GHz
- **Turbo Clock**: 3.20 GHz

### Dragonfruit (AMD Host)
- **CPU**: AMD Ryzen 7 2700X
- **Total Resources**: 8 cores / 16 threads
- **Base Clock**: 3.7 GHz
- **Turbo Clock**: 4.35 GHz

## Current K8s VM Allocations (from cluster inspection)

### Control Plane Nodes (dungeon-map-*)
- **Current Config**: 2 sockets × 2 cores = 4 vCPUs each
- **Threads per core**: 1 (no hyperthreading exposed)

### Worker Nodes (dungeon-chest-*)
- **Current Config**: 2 sockets × 6 cores = 12 vCPUs each (chest-004: 10 vCPUs)
- **Threads per core**: 1 (no hyperthreading exposed)

## Recommended Proxmox CPU Settings

### Philosophy: 1 vCPU = 1 Physical Thread

**Why this approach:**
- Kubernetes scheduler sees accurate CPU capacity
- Better NUMA awareness for memory locality
- Realistic resource scheduling (no overcommit confusion)
- Improved cache efficiency within socket boundaries
- Matches how modern schedulers expect topology

### Recommended Configuration

#### Worker Nodes (dungeon-chest-*)

```
Sockets: 2
Cores per socket: 6-8 (depending on host capacity)
Total vCPUs: 12-16
Enable NUMA: ✓ (CRITICAL for multi-socket awareness)
CPU type: host (exposes full CPU features + NUMA topology)
```

**Result**: Each worker gets 12-16 threads, respecting physical NUMA domains

#### Control Plane Nodes (dungeon-map-*)

```
Sockets: 2
Cores per socket: 2
Total vCPUs: 4
Enable NUMA: ✓
CPU type: host
```

**Result**: Control plane gets 4 threads (sufficient for API server, etcd, controller-manager, scheduler)

### Why Enable NUMA?

1. **Kubernetes topology awareness**: K8s can see socket topology via `topology.kubernetes.io/zone`
2. **Memory locality**: Workloads stay on same socket's memory controller (lower latency)
3. **Cache efficiency**: Better L3 cache hit rates within same socket
4. **Realistic scheduling**: K8s sees actual NUMA domains for topology-aware scheduling

### Why CPU Type: host?

1. Exposes full CPU instruction sets to guest (AVX, etc.)
2. Better performance (no instruction translation overhead)
3. Required for proper NUMA topology exposure to guest OS
4. K8s can see accurate CPU model information

## Resource Allocation Per Physical Host

### 🥑 Avocado (256GB RAM, RTX A2000, 40 threads total)

| VM | Purpose | CPU Config | vCPUs | Notes |
|----|---------|------------|-------|-------|
| dungeon-chest-001 | K8s Worker | 2 sockets × 8 cores | 16 | Primary worker with GPU passthrough potential |
| pfSense HA Primary | Firewall | 2 sockets × 2 cores | 4 | HA primary node |
| Windows Server | Workloads | 2 sockets × 4 cores | 8 | General Windows workloads |
| FusionPBX | VoIP | 2 sockets × 2 cores | 4 | Phone system |
| **Reserve** | Host + Flexibility | - | ~8 | Proxmox overhead, FRR/OSPF, dev VMs |

**RTX A2000 12GB**: Can passthrough to dungeon-chest-001 or Windows Server

### 🎍 Bamboo (96GB RAM, 40 threads total)

| VM | Purpose | CPU Config | vCPUs | Notes |
|----|---------|------------|-------|-------|
| dungeon-chest-002 | K8s Worker | 2 sockets × 8 cores | 16 | Standard worker |
| pfSense HA Secondary | Firewall | 2 sockets × 2 cores | 4 | HA secondary node |
| Windows Server | Workloads | 2 sockets × 4 cores | 8 | General Windows workloads |
| **Reserve** | Host + Flexibility | - | ~12 | Largest reserve for FRR/OSPF/dev |

**Note**: Lower RAM means reserve more threads for lightweight VMs

### 🌌 Cosmos (256GB RAM, 40 threads total)

| VM | Purpose | CPU Config | vCPUs | Notes |
|----|---------|------------|-------|-------|
| dungeon-chest-003 | K8s Worker | 2 sockets × 10 cores | 20 | High-capacity worker |
| dungeon-map-001 | K8s Control | 2 sockets × 2 cores | 4 | Control plane node |
| Windows Server | Workloads | 2 sockets × 4 cores | 8 | General Windows workloads |
| **Reserve** | Host + Flexibility | - | ~8 | Proxmox overhead, additional VMs |

**Note**: High RAM makes this good for memory-intensive workloads

### 🍆 Eggplant (128GB RAM, 40 threads total)

| VM | Purpose | CPU Config | vCPUs | Notes |
|----|---------|------------|-------|-------|
| dungeon-chest-005 | K8s Worker | 2 sockets × 8 cores | 16 | Standard worker |
| dungeon-map-002 | K8s Control | 2 sockets × 2 cores | 4 | Control plane node |
| TrueNAS | Storage | 2 sockets × 4 cores | 8 | NAS storage management |
| Proxmox Backup Server | Backup | 2 sockets × 2 cores | 4 | PBS backup server |
| **Reserve** | Host + Flexibility | - | ~8 |  |

**Note**: Storage and backup workloads here

### 🐉 Dragonfruit (64GB RAM, AMD Ryzen 8C/16T)

| VM | Purpose | CPU Config | vCPUs | Notes |
|----|---------|------------|-------|-------|
| dungeon-chest-004 | K8s Worker | 1 socket × 10 cores | 10 | GPU node with GTX 980 Ti |
| **Reserve** | Host + Flexibility | - | ~6 | Proxmox overhead |

**GTX 980 Ti**: Passthrough to dungeon-chest-004 (already configured)

**Note**: Most constrained host - only running K8s worker with GPU. Ryzen doesn't have traditional multi-socket NUMA, but proper core allocation still helps. Single socket config is fine here.

## Total Kubernetes Cluster Capacity

### Control Plane
- 5 nodes × 4 vCPUs = **20 vCPUs total**
- Sufficient for API server, etcd, scheduler, controller-manager across 5 nodes

### Workers
- chest-001: 16 vCPUs
- chest-002: 12 vCPUs
- chest-003: 16 vCPUs
- chest-004: 10 vCPUs
- chest-005: 12 vCPUs
- **Total: 66 vCPUs for workloads**

### Cluster-Wide Reserve
- ~60 threads reserved across all hosts for:
  - Proxmox host overhead (~10 threads)
  - pfSense HA pair (8 threads)
  - Windows Servers (24 threads)
  - TrueNAS + PBS (12 threads)
  - FusionPBX (4 threads) - on Avocado
  - FRR/OSPF routing VMs
  - Development/test VMs
  - Future expansion

## Migration Procedure

### To Increase Worker vCPUs (e.g., 12 → 16)

1. **Drain the node:**
   ```bash
   kubectl drain dungeon-chest-001 --ignore-daemonsets --delete-emptydir-data
   ```

2. **Shutdown the VM** in Proxmox UI or CLI:
   ```bash
   qm shutdown <vmid>
   ```

3. **Edit VM CPU settings** in Proxmox:
   - Navigate to VM → Hardware → Processors
   - Set Sockets: 2
   - Set Cores: 8 (was 6 for 12 vCPUs)
   - Enable NUMA: ✓
   - CPU type: host
   - Click OK

4. **Start the VM:**
   ```bash
   qm start <vmid>
   ```

5. **Verify CPU allocation** on the node:
   ```bash
   ssh dungeon-chest-001 'lscpu | grep -E "^CPU\(s\)|Thread|Core|Socket"'
   ```
   Should show: CPU(s): 16

6. **Uncordon the node:**
   ```bash
   kubectl uncordon dungeon-chest-001
   ```

7. **Verify Kubernetes sees the new capacity:**
   ```bash
   kubectl get node dungeon-chest-001 -o json | jq '.status.capacity.cpu'
   ```
   Should show: "16"

8. **Verify NUMA topology** (optional):
   ```bash
   ssh dungeon-chest-001 'numactl --hardware'
   ```

### Important Notes for Migration

- **Do one node at a time** to maintain cluster availability
- **Monitor workload distribution** after uncordoning to ensure scheduling is working
- **Control plane nodes** can typically stay at 4 vCPUs unless experiencing resource pressure
- **Test on one worker first** before rolling out to all workers

## Benefits of This Configuration

### For Kubernetes
1. **Accurate capacity planning**: Scheduler sees real thread counts
2. **Better workload distribution**: No CPU overcommit confusion
3. **NUMA-aware scheduling**: Can use topology hints for memory-intensive workloads
4. **Predictable performance**: 1:1 vCPU:thread mapping eliminates scheduling jitter

### For Proxmox
1. **Clear resource accounting**: Know exactly what's allocated vs available
2. **Easier capacity planning**: Simple math for VM placement
3. **Better host stability**: Leave 10-20% reserve prevents host CPU starvation
4. **Flexibility maintained**: 50+ threads reserved cluster-wide for additional VMs

### For Workloads
1. **Lower latency**: NUMA locality keeps memory access on same socket
2. **Better cache utilization**: Workloads stay within socket boundaries when possible
3. **Consistent performance**: No CPU time-slicing between vCPUs fighting for same thread
4. **GPU affinity**: NUMA awareness helps with GPU passthrough locality

## Monitoring and Validation

### Check Current CPU Allocation in Proxmox

Via CLI on each Proxmox host:
```bash
# List all VMs with CPU allocation
qm list | awk '{print $1}' | tail -n +2 | while read vmid; do
  echo "VM $vmid: $(qm config $vmid | grep -E 'cores|sockets|numa')"
done
```

### Check Kubernetes Node Capacity

```bash
# See CPU and memory capacity/allocatable for all nodes
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
CPU_CAPACITY:.status.capacity.cpu,\
CPU_ALLOCATABLE:.status.allocatable.cpu,\
MEMORY_CAPACITY:.status.capacity.memory,\
MEMORY_ALLOCATABLE:.status.allocatable.memory
```

### Check NUMA Topology from K8s Node

```bash
# SSH to a node and check NUMA topology
ssh dungeon-chest-001 'numactl --hardware'

# Should show 2 NUMA nodes (one per socket) with cores distributed properly
```

### Monitor CPU Usage

```bash
# Check CPU usage on Proxmox host
top
htop

# Check CPU usage in Kubernetes
kubectl top nodes
kubectl top pods -A
```

## Troubleshooting

### Q: Should I enable CPU hotplug?
**A:** No. Keep it disabled. Kubernetes doesn't handle CPU hotplug well, and it can cause scheduling issues.

### Q: What about CPU limits/balloon/shares in Proxmox?
**A:**
- **CPU limit**: Leave at default (unlimited)
- **CPU units**: Leave at default (1024) for equal priority
- **Only adjust** if you need to prioritize certain VMs (e.g., pfSense > others)

### Q: Should I pin vCPUs to specific physical cores?
**A:** Generally no. Let Proxmox handle scheduling unless you have specific latency requirements (e.g., real-time workloads).

### Q: What if I need more CPU for workers?
**A:** Options:
1. Reduce Windows Server allocations (8 → 6 cores)
2. Reduce reserve buffer (risk host starvation)
3. Add more physical Proxmox hosts
4. Migrate some VMs to different hosts to rebalance

### Q: Why not overcommit CPU (give more vCPUs than physical threads)?
**A:**
- Kubernetes scheduling assumptions break with overcommit
- Performance becomes unpredictable under load
- CPU steal time increases
- Better to have accurate capacity than overcommitted resources

## Summary Recommendation

**Use 1 vCPU per physical thread with proper NUMA topology:**

### Workers
- **Sockets**: 2
- **Cores per socket**: 6-8 (12-16 vCPUs total)
- **NUMA**: Enabled ✓
- **CPU type**: host

### Control Plane
- **Sockets**: 2
- **Cores per socket**: 2 (4 vCPUs total)
- **NUMA**: Enabled ✓
- **CPU type**: host

This configuration:
- Gives K8s **66 worker vCPUs** across 5 nodes (was 58 with current config)
- Leaves **~64 threads** (32%) cluster-wide for other VMs and host overhead
- Enables NUMA awareness for better memory locality
- Provides accurate CPU capacity for scheduling
- Maintains flexibility for FRR/OSPF routing and dev VMs
