# Named RBD Strategy: Eliminating PVC Sprawl

## The Problem You Identified

1. **Orphan PVCs**: StatefulSet `volumeClaimTemplates` create PVCs on startup, leave orphans on rescale (2.2 TiB waste)
2. **Unpredictable names**: Auto-generated PVC/PV names make Ceph operations difficult (`rbd ls dungeon` shows gibberish)
3. **Foolish replication**: Applications adding replication on top of Ceph 4x foundation (Kafka 3×4=12 copies!)

## The Solution: Static PV/PVC + CSI Auto-Creation

### How It Works

1. **Create PersistentVolumes** with explicit `volumeHandle` names
2. **Create PersistentVolumeClaims** with explicit `volumeName` binding
3. **Ceph CSI automatically creates RBDs** if `volumeHandle` doesn't exist (idempotent!)
4. **Use Deployment instead of StatefulSet** for apps that don't need ordering
5. **Reference pre-created PVCs** in Deployment `volumes:`

### Benefits

- Named RBDs: `swift-sail-qbittorrent-downloads-0` (easy to track in Ceph)
- No orphan PVCs (you control lifecycle)
- Idempotent (CSI creates RBD if missing, no manual provisioning needed)
- Simple, no scripting required
- Works with FluxCD GitOps

## StatefulSet vs Deployment Decision Tree

### Use Deployment When:
- App doesn't need ordered startup/shutdown (qBittorrent, Open-WebUI, Homarr, Homepage)
- Single replica OR replicas are independent
- You want full control over PVC lifecycle

**Result**: Pre-create PVs/PVCs, reference in Deployment `volumes:`

### Use StatefulSet When:
- Database cluster with ordered initialization (PostgreSQL HA, Etcd, Cassandra)
- Stateful distributed systems requiring stable network IDs (Kafka, ZooKeeper)
- Sequential startup/shutdown is critical

**Result**: Still pre-create PVs/PVCs, reference in `volumes:` instead of `volumeClaimTemplates:`

## Example: qBittorrent Named RBDs

### Step 1: Create Static PersistentVolumes

File: `/srv/dungeon/fluxcd/infrastructure/storage/overlays/production/swift-sail/persistent-volumes.yaml`

```yaml
# Gluetun VPN config (small, persistent)
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: swift-sail-gluetun-config-0
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain  # Protects RBD from deletion
  storageClassName: ceph-rbd-static
  csi:
    driver: rbd.csi.ceph.com
    fsType: ext4
    volumeHandle: swift-sail-gluetun-config-0  # This becomes RBD name in Ceph
    volumeAttributes:
      clusterID: "0985467c-d8f3-4483-b27f-f0a512397ec2"  # Your Ceph FSID
      pool: dungeon
      staticVolume: "true"
      imageFeatures: layering
    nodeStageSecretRef:
      name: ceph-rbd-secret
      namespace: kube-system

# qBittorrent config (app settings)
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: swift-sail-qbittorrent-config-0
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ceph-rbd-static
  csi:
    driver: rbd.csi.ceph.com
    fsType: ext4
    volumeHandle: swift-sail-qbittorrent-config-0
    volumeAttributes:
      clusterID: "0985467c-d8f3-4483-b27f-f0a512397ec2"
      pool: dungeon
      staticVolume: "true"
      imageFeatures: layering
    nodeStageSecretRef:
      name: ceph-rbd-secret
      namespace: kube-system

# qBittorrent downloads (large, active torrents)
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: swift-sail-qbittorrent-downloads-0
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ceph-rbd-static
  csi:
    driver: rbd.csi.ceph.com
    fsType: ext4
    volumeHandle: swift-sail-qbittorrent-downloads-0  # Easy to find: rbd ls dungeon | grep swift-sail
    volumeAttributes:
      clusterID: "0985467c-d8f3-4483-b27f-f0a512397ec2"
      pool: dungeon
      staticVolume: "true"
      imageFeatures: layering
    nodeStageSecretRef:
      name: ceph-rbd-secret
      namespace: kube-system
```

### Step 2: Create Static PersistentVolumeClaims

File: `/srv/dungeon/fluxcd/infrastructure/storage/overlays/production/swift-sail/persistent-volume-claims.yaml`

```yaml
# Gluetun config PVC
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: swift-sail-gluetun-config
  namespace: swift-sail
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-rbd-static
  volumeName: swift-sail-gluetun-config-0  # Explicit bind to specific PV
  resources:
    requests:
      storage: 5Gi

# qBittorrent config PVC
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: swift-sail-qbittorrent-config
  namespace: swift-sail
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-rbd-static
  volumeName: swift-sail-qbittorrent-config-0
  resources:
    requests:
      storage: 10Gi

# qBittorrent downloads PVC
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: swift-sail-qbittorrent-downloads
  namespace: swift-sail
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-rbd-static
  volumeName: swift-sail-qbittorrent-downloads-0
  resources:
    requests:
      storage: 100Gi
```

### Step 3: Convert StatefulSet to Deployment

**OLD**: StatefulSet with `volumeClaimTemplates` (creates orphans)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: qbittorrent
spec:
  volumeClaimTemplates:  # PROBLEM: Creates PVCs automatically, orphans on rescale
  - metadata:
      name: gluetun-config
    spec:
      storageClassName: ceph-rbd
      resources:
        requests:
          storage: 5Gi
```

**NEW**: Deployment with pre-created PVCs (no orphans)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qbittorrent
spec:
  replicas: 1  # qBittorrent can't share downloads (ReadWriteOnce)
  selector:
    matchLabels:
      app: qbittorrent
  template:
    metadata:
      labels:
        app: qbittorrent
    spec:
      containers:
      - name: gluetun
        image: qmcgaw/gluetun:latest
        volumeMounts:
        - name: gluetun-config
          mountPath: /gluetun
      - name: qbittorrent
        image: lscr.io/linuxserver/qbittorrent:latest
        volumeMounts:
        - name: qbittorrent-config
          mountPath: /config
        - name: qbittorrent-downloads
          mountPath: /downloads

      volumes:
      - name: gluetun-config
        persistentVolumeClaim:
          claimName: swift-sail-gluetun-config  # Pre-created PVC
      - name: qbittorrent-config
        persistentVolumeClaim:
          claimName: swift-sail-qbittorrent-config
      - name: qbittorrent-downloads
        persistentVolumeClaim:
          claimName: swift-sail-qbittorrent-downloads
```

## How CSI Auto-Creation Works

When you apply the PV with `volumeHandle: swift-sail-qbittorrent-downloads-0`:

1. **CSI checks Ceph**: Does RBD `dungeon/swift-sail-qbittorrent-downloads-0` exist?
2. **If NO**: CSI creates it with the size from PV spec (100Gi)
3. **If YES**: CSI mounts existing RBD (idempotent!)
4. **Result**: Named RBD in Ceph, no manual provisioning needed

## Verifying in Ceph

On Proxmox Ceph cluster:

```bash
# List all swift-sail RBDs (easy to find with naming convention)
rbd ls dungeon | grep swift-sail

# Expected output:
swift-sail-gluetun-config-0
swift-sail-qbittorrent-config-0
swift-sail-qbittorrent-downloads-0

# Check RBD details
rbd info dungeon/swift-sail-qbittorrent-downloads-0

# Expected output:
rbd image 'swift-sail-qbittorrent-downloads-0':
        size 100 GiB in 25600 objects
        order 22 (4 MiB objects)
        snapshot_count: 0
        id: 12345abcdef
        block_name_prefix: rbd_data.12345abcdef
        format: 2
        features: layering
        op_features:
        flags:
        create_timestamp: ...
        access_timestamp: ...
        modify_timestamp: ...

# Monitor RBD usage over time
rbd du dungeon/swift-sail-qbittorrent-downloads-0
```

## Migration Plan: Eliminate Orphan PVCs

### Phase 1: Identify Current Orphans (DONE)

Found 2.2 TiB of orphaned PVCs from apps:
- swift-sail: 1,012Gi (qBittorrent duplicates from StatefulSet rescales)
- immich: 570Gi
- Prometheus/Thanos: 360Gi
- Kafka: 200Gi

### Phase 2: Convert Apps to Deployment Pattern

Priority apps (largest storage impact):

1. **qBittorrent** (1,012Gi orphans)
   - Create static PVs/PVCs (DONE)
   - Convert StatefulSet → Deployment (READY TO APPLY)
   - Clean up orphan PVCs after migration

2. **Immich** (570Gi orphans)
   - Create static PVs for: library, model-cache, postgres
   - Convert to Deployment pattern

3. **Open-WebUI** (multiple replicas, no ordering needed)
   - Create static PVs/PVCs per replica (or use single RWX on CephFS)
   - Convert StatefulSet → Deployment

### Phase 3: Clean Up Orphans

After migrating apps to Deployment pattern:

```bash
# List orphaned PVCs (not mounted by any pod)
kubectl get pvc --all-namespaces -o json | jq -r '
  .items[] |
  select(.metadata.namespace == "swift-sail") |
  "\(.metadata.name) \(.spec.resources.requests.storage)"
'

# Delete confirmed orphans (AFTER verifying data is migrated)
kubectl delete pvc -n swift-sail <orphan-pvc-name>
```

## When to Still Use StatefulSets

For apps requiring ordered initialization, you can STILL use this pattern:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-ha
spec:
  replicas: 3
  template:
    spec:
      volumes:
      - name: postgres-data
        persistentVolumeClaim:
          claimName: postgres-ha-data-0  # Pre-created, NOT volumeClaimTemplate
```

**Key**: Pre-create PVs/PVCs, reference in `volumes:` instead of `volumeClaimTemplates:`

## Storage Class Configuration

Create `ceph-rbd-static` storage class for static provisioning:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-rbd-static
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: "0985467c-d8f3-4483-b27f-f0a512397ec2"
  pool: dungeon
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: ceph-rbd-secret
  csi.storage.k8s.io/provisioner-secret-namespace: kube-system
  csi.storage.k8s.io/controller-expand-secret-name: ceph-rbd-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: kube-system
  csi.storage.k8s.io/node-stage-secret-name: ceph-rbd-secret
  csi.storage.k8s.io/node-stage-secret-namespace: kube-system
volumeBindingMode: Immediate
reclaimPolicy: Retain  # Protect data
allowVolumeExpansion: true
```

## Summary

**You Asked**: Can StatefulSets use named volumeHandles?

**Answer**: No, but you don't need StatefulSets for most apps.

**Solution**:
1. Pre-create PVs with named `volumeHandle` (CSI creates RBD automatically)
2. Pre-create PVCs with explicit `volumeName` binding
3. Use Deployment + reference PVCs in `volumes:`
4. NO MORE ORPHAN PVCs, named RBDs for tracking

**Files Created**:
- `/srv/dungeon/fluxcd/infrastructure/storage/overlays/production/swift-sail/persistent-volumes.yaml`
- `/srv/dungeon/fluxcd/infrastructure/storage/overlays/production/swift-sail/persistent-volume-claims.yaml`
- `/srv/dungeon/fluxcd/infrastructure/storage/overlays/production/swift-sail/kustomization.yaml`

**Next Steps**:
1. Apply storage overlay: `flux reconcile kustomization infrastructure-storage-swift-sail`
2. Verify RBDs created in Ceph: `rbd ls dungeon | grep swift-sail`
3. Convert qBittorrent StatefulSet → Deployment
4. Clean up orphan PVCs after migration
