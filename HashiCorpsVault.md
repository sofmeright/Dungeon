# HashiCorp Vault Recovery and Bootstrap Process

## Overview
This document outlines the process to recover or bootstrap HashiCorp Vault in the Kubernetes cluster when data is lost or Vault needs to be reinitialized.

## Background
Vault data can be lost if the PVC is deleted while using `Delete` reclaim policy. Always use `Retain` policy for stateful services.

## Prerequisites
- Access to the Kubernetes cluster
- SOPS configured for encrypting/decrypting secrets
- Bank-vaults operator installed in the cluster

## Storage Class Configuration (CRITICAL)
Before deploying Vault, ensure you're using a storage class with `Retain` policy to prevent data loss:

```yaml
# Located at: fluxcd/infrastructure/configs/base/storage/ceph-rbd-retain-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ceph-rbd-retain
reclaimPolicy: Retain  # CRITICAL: Prevents data loss when PVC is deleted
```

Vault PVC configuration should reference this storage class:
```yaml
# Located at: fluxcd/infrastructure/controllers/base/vault/pvc.yaml
storageClassName: ceph-rbd-retain
```

## Vault Bootstrap Process

### 1. Check Current Vault State
```bash
# Check if Vault pod is running
kubectl get pod -n prplanit-atlas vault-0

# Check Vault initialization status
kubectl exec -n prplanit-atlas vault-0 -c vault -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 vault status'
```

### 2. If Vault Data is Lost (Complete Reinitialization)

#### Step 2.1: Clean up existing resources
```bash
# Delete the StatefulSet (operator will recreate it)
kubectl delete statefulset -n prplanit-atlas vault

# Delete the old PVC if it exists
kubectl delete pvc -n prplanit-atlas vault-data

# If PVC is stuck terminating, remove finalizers
kubectl patch pvc -n prplanit-atlas vault-data -p '{"metadata":{"finalizers":null}}'
```

#### Step 2.2: Remove old unseal keys
```bash
# Delete the old unseal keys secret
# Bank-vaults will create new ones during initialization
kubectl delete secret -n prplanit-atlas vault-unseal-keys
```

#### Step 2.3: Create new PVC with retain storage class
```bash
kubectl apply -f fluxcd/infrastructure/controllers/base/vault/pvc.yaml
```

#### Step 2.4: Restart the operator to recreate StatefulSet
```bash
kubectl delete pod -n bank-vaults-system -l app.kubernetes.io/name=vault-operator
```

#### Step 2.5: Wait for Vault to initialize
```bash
# Watch the pod come up
kubectl get pod -n prplanit-atlas vault-0 -w

# Check logs if there are issues
kubectl logs -n prplanit-atlas vault-0 -c bank-vaults
```

### 3. Save New Unseal Keys to SOPS

After Vault reinitializes, bank-vaults creates new unseal keys. These MUST be saved:

#### Step 3.1: Export the new unseal keys
```bash
# Export the secret to a file
kubectl get secret -n prplanit-atlas vault-unseal-keys -o yaml | \
  grep -v "resourceVersion\|uid\|creationTimestamp\|time:" | \
  grep -v "kubectl.kubernetes.io" > /tmp/vault-unseal-keys.yaml
```

#### Step 3.2: Save to the repository
```bash
# Copy to the vault config directory
cp /tmp/vault-unseal-keys.yaml fluxcd/infrastructure/configs/overlays/production/vault/vault-unseal-keys.enc.yaml
```

#### Step 3.3: Encrypt with SOPS
```bash
# Encrypt the file in place
sops -e -i fluxcd/infrastructure/configs/overlays/production/vault/vault-unseal-keys.enc.yaml
```

#### Step 3.4: Update kustomization to include the keys
```yaml
# fluxcd/infrastructure/configs/overlays/production/vault/kustomization.yaml
resources:
  - vault-unseal-keys.enc.yaml  # SOPS-encrypted unseal keys
```

#### Step 3.5: Commit and push
```bash
git add fluxcd/infrastructure/configs/overlays/production/vault/
git commit -m "Update Vault unseal keys after reinitialization"
git push
```

## Troubleshooting

### Issue: "security barrier not initialized"
This is normal for a sealed Vault. The bank-vaults sidecar should automatically unseal it using the keys from the Kubernetes secret.

### Issue: "value for key 'vault-root' already exists"
This happens when bank-vaults tries to initialize an already-initialized Vault, but the secret already contains a root token. This typically indicates:
- The Vault data on disk doesn't match the unseal keys in the secret
- The Vault data was lost but the old keys still exist

**Solution**: Follow the complete reinitialization process above.

### Issue: Startup probe failing
The default startup probe checks `/v1/sys/init` which fails for sealed vaults. If this causes issues:
```bash
# Remove the startup probe
kubectl patch statefulset -n prplanit-atlas vault --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/startupProbe"}]'
```

### Issue: PVC stuck terminating
```bash
# Force remove finalizers
kubectl patch pvc -n prplanit-atlas vault-data -p '{"metadata":{"finalizers":null}}'
```

## Important Files and Locations

- **Vault CR**: `fluxcd/infrastructure/controllers/base/vault/vault-cr.yaml`
- **Vault PVC**: `fluxcd/infrastructure/controllers/base/vault/pvc.yaml`
- **SOPS-encrypted unseal keys**: `fluxcd/infrastructure/configs/overlays/production/vault/vault-unseal-keys.enc.yaml`
- **Storage class**: `fluxcd/infrastructure/configs/base/storage/ceph-rbd-retain-storageclass.yaml`
- **SOPS configuration**: `.sops.yaml` (in repository root)

## Key Components

1. **Vault Pod** (vault-0): Contains 3 containers:
   - `vault`: The actual HashiCorp Vault server
   - `bank-vaults`: Handles auto-unsealing and initialization
   - `prometheus-exporter`: Metrics exporter

2. **Bank-vaults Operator**: Manages the Vault StatefulSet and configuration

3. **Unseal Keys Secret**: Kubernetes secret containing the Shamir unseal keys and root token

## Best Practices

1. **Always use Retain reclaim policy** for Vault's PVC
2. **Backup unseal keys** immediately after initialization
3. **Store unseal keys encrypted with SOPS** in the Git repository
4. **Never commit unencrypted unseal keys** to Git
5. **Test recovery process** in a non-production environment

## References

- Commit ac8d1b9: "Fix Vault data loss: Add Retain storage class and reinitialize Vault"
- Bank-vaults documentation: https://bank-vaults.dev/
- HashiCorp Vault documentation: https://www.vaultproject.io/docs