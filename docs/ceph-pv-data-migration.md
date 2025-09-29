# Ceph PV Data Migration Guide

This guide documents how to migrate data from old Ceph Persistent Volumes to new ones when there are configuration mismatches (like incorrect secret namespaces).

## Overview

This process is needed when:
- Old PVs reference secrets in the wrong namespace (e.g., `ceph-csi` instead of `prplanit-atlas`)
- PV specs are immutable and can't be patched
- You need to preserve data while fixing configuration issues
- Storage class configurations have changed

## Prerequisites

- Access to both old and new PVCs
- Ability to create temporary namespaces and pods
- Knowledge of the correct Ceph secrets and their location

## Step-by-Step Process

### 1. Identify the Problem

Check if old PVs are failing to mount due to secret namespace issues:

```bash
kubectl describe pv <pv-name>
kubectl get events -n <namespace> --field-selector involvedObject.kind=Pod
```

Look for errors like:
```
failed to find the secret ceph-secret-user in the namespace ceph-csi
```

### 2. Locate Source Data

Find the PVs containing your data:

```bash
kubectl get pv | grep <app-name>
kubectl get pv <pv-name> -o yaml
```

Note the PV names that contain your data (usually in `Released` status).

### 3. Create Temporary Secret Namespace

If old PVs reference secrets in a namespace that doesn't exist or has incorrect secrets:

```bash
# Create the namespace the old PVs expect
kubectl create namespace ceph-csi

# Copy the correct secrets from the actual location
kubectl get secret ceph-secret -n prplanit-atlas -o yaml | \
  sed 's/namespace: prplanit-atlas/namespace: ceph-csi/' | \
  kubectl apply -f -

kubectl get secret ceph-secret-user -n prplanit-atlas -o yaml | \
  sed 's/namespace: prplanit-atlas/namespace: ceph-csi/' | \
  kubectl apply -f -
```

### 4. Create Old PVCs

Create PVCs that bind to the old PVs containing your data:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: old-app-conf
  namespace: your-namespace
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  volumeName: pvc-old-volume-id-here
  storageClassName: ceph-rbd-retain
```

### 5. Remove Claim References from Old PVs

```bash
kubectl patch pv <old-pv-name> --type=json -p='[{"op": "remove", "path": "/spec/claimRef"}]'
```

### 6. Verify PVC Binding

```bash
kubectl get pvc -n your-namespace
```

Ensure both old and new PVCs show `Bound` status.

### 7. Create Migration Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: data-migration
  namespace: your-namespace
spec:
  containers:
  - name: migration
    image: docker.io/alpine:latest
    command: ["sleep", "3600"]
    volumeMounts:
    - name: old-conf
      mountPath: /old-conf
    - name: old-data
      mountPath: /old-data
    - name: new-conf
      mountPath: /new-conf
    - name: new-data
      mountPath: /new-data
  volumes:
  - name: old-conf
    persistentVolumeClaim:
      claimName: old-app-conf
  - name: old-data
    persistentVolumeClaim:
      claimName: old-app-data
  - name: new-conf
    persistentVolumeClaim:
      claimName: app-conf
  - name: new-data
    persistentVolumeClaim:
      claimName: app-data
  restartPolicy: Never
```

### 8. Perform Data Copy

Wait for the pod to be running, then copy the data:

```bash
# Verify old data exists
kubectl exec -n your-namespace data-migration -- ls -la /old-conf
kubectl exec -n your-namespace data-migration -- ls -la /old-data

# Copy configuration files
kubectl exec -n your-namespace data-migration -- cp -a /old-conf/* /new-conf/

# Copy data directories
kubectl exec -n your-namespace data-migration -- cp -a /old-data/* /new-data/

# Verify copy succeeded
kubectl exec -n your-namespace data-migration -- ls -la /new-conf
kubectl exec -n your-namespace data-migration -- ls -la /new-data
```

### 9. Restart Application

```bash
kubectl rollout restart deployment/your-app -n your-namespace
kubectl rollout status deployment/your-app -n your-namespace
```

### 10. Verify Application

Check that your application is running and has access to the migrated data:

```bash
kubectl get pods -n your-namespace -l app=your-app
kubectl logs -n your-namespace deployment/your-app
```

### 11. Clean Up Migration Resources

```bash
# Delete migration pod
kubectl delete pod data-migration -n your-namespace

# Delete old PVCs
kubectl delete pvc old-app-conf old-app-data -n your-namespace

# Delete temporary namespace (if created)
kubectl delete namespace ceph-csi

# Clean up any temporary files
rm -f /tmp/old-pvcs.yaml /tmp/data-migration.yaml
```

## Troubleshooting

### Pod Won't Schedule
- Check PVC binding status: `kubectl get pvc -n your-namespace`
- Verify PV availability: `kubectl get pv | grep Available`
- Check events: `kubectl get events -n your-namespace`

### Image Pull Issues
- Use fully qualified image names: `docker.io/alpine:latest`
- Check node container runtime configuration

### Mount Failures
- Verify secret existence in the expected namespace
- Check Ceph cluster connectivity
- Ensure CSI driver is running: `kubectl get pods -n rook-ceph | grep csi`

### Data Copy Failures
- Check file permissions in source volumes
- Verify sufficient disk space in destination volumes
- Use `cp -a` to preserve attributes and permissions

## Important Notes

- **Always backup data before starting migration**
- **Test the process in a non-production environment first**
- **Monitor disk space during the copy process**
- **The old PVs will be deleted when old PVCs are removed (if ReclaimPolicy is Delete)**
- **Keep old PVs with `Retain` policy until migration is verified successful**

## Example: AdGuard Migration

This process was successfully used to migrate AdGuard DNS data from PVs with incorrect secret namespace references to new properly configured PVs, preserving all configuration and filter lists.

## Recovery

If migration fails:
1. Don't delete old PVCs until new deployment is verified working
2. Old PVs with `Retain` policy will remain available for retry
3. You can recreate the migration pod and repeat the copy process
4. Application can be rolled back to use old PVCs if needed