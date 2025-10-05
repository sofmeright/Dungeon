# Vault Kubernetes Authentication Setup Guide

This guide documents how to properly configure Vault's Kubernetes authentication method for use with External Secrets.

## Prerequisites

1. Vault is running and unsealed
2. You have a Vault root token or appropriate permissions
3. External Secrets is deployed in the cluster
4. ServiceAccount for External Secrets exists with proper ClusterRole binding

## Step 1: Enable Kubernetes Auth Method

```bash
# Enable the Kubernetes auth method
vault auth enable kubernetes
```

## Step 2: Configure Kubernetes Auth Method

Get the required information from the cluster:

```bash
# Get the Kubernetes API server URL
K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Alternative if running inside the cluster:
K8S_HOST="https://kubernetes.default.svc.cluster.local"
```

Configure Vault with the Kubernetes cluster information:

```bash
# Get the ServiceAccount token for Vault to use as reviewer
REVIEWER_TOKEN=$(kubectl get secret external-secrets-vault-token -n prplanit-atlas -o jsonpath='{.data.token}' | base64 -d)

vault write auth/kubernetes/config \
    kubernetes_host="${K8S_HOST}" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    issuer="${K8S_HOST}" \
    token_reviewer_jwt="${REVIEWER_TOKEN}"
```

## Step 3: Create Vault Policy

Create a policy that grants the necessary permissions:

```bash
vault policy write external-secrets - <<EOF
path "secret/*" {
  capabilities = ["read", "list"]
}
path "operationtimecapsule/*" {
  capabilities = ["read", "list"]
}
EOF
```

## Step 4: Create Kubernetes Auth Role

Create a role that binds the ServiceAccount to the policy:

```bash
vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=external-secrets-vault \
    bound_service_account_namespaces=prplanit-atlas \
    policies=external-secrets \
    ttl=24h
```

## Step 5: Create ServiceAccount and ClusterRole Binding

The ServiceAccount needs the `system:auth-delegator` ClusterRole to allow Vault to validate tokens:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-vault
  namespace: prplanit-atlas
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-secrets-vault-auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: external-secrets-vault
  namespace: prplanit-atlas
---
apiVersion: v1
kind: Secret
metadata:
  name: external-secrets-vault-token
  namespace: prplanit-atlas
  annotations:
    kubernetes.io/service-account.name: external-secrets-vault
type: kubernetes.io/service-account-token
```

## Step 6: Configure ClusterSecretStore

Create the ClusterSecretStore that uses Kubernetes authentication:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault.prplanit-atlas.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: "external-secrets-vault"
            namespace: "prplanit-atlas"
```

## Troubleshooting

### Permission Denied Errors

If you get "permission denied" errors:

1. **Check token_reviewer_jwt_set**: Run `vault read auth/kubernetes/config` and verify `token_reviewer_jwt_set` is `true`
   - If false, this is the most common cause of 403 errors
   - Follow the configuration step above to set the `token_reviewer_jwt`
2. Verify the ServiceAccount exists and has the token secret
3. Check that the ClusterRole binding exists for `system:auth-delegator`
4. Ensure the Vault role name matches exactly
5. Verify the bound ServiceAccount names and namespaces in the Vault role
6. Check that the Kubernetes auth method is properly configured with CA cert and issuer
7. Verify External Secrets ClusterRole has `serviceaccounts/token` create permission

### Testing Authentication

You can test authentication manually:

```bash
# Get the ServiceAccount token
SA_TOKEN=$(kubectl get secret external-secrets-vault-token -n prplanit-atlas -o jsonpath='{.data.token}' | base64 -d)

# Test authentication with Vault
vault write auth/kubernetes/login role=external-secrets jwt="${SA_TOKEN}"
```

### Common Issues

- **Missing token_reviewer_jwt**: The #1 cause of 403 errors - Vault needs a ServiceAccount token to validate other tokens
- **Wrong ServiceAccount**: Ensure the serviceAccountRef in the ClusterSecretStore matches the actual ServiceAccount
- **Missing ClusterRole binding**: The `system:auth-delegator` ClusterRole is required
- **Corrupted ServiceAccount token**: Delete and recreate the ServiceAccount token secret if it appears empty
- **Wrong secret paths**: For KV v2, use paths like `operationtimecapsule/smb/secret` not `operationtimecapsule/data/smb/secret`
- **Vault configuration**: CA cert and issuer must be properly configured
- **Network connectivity**: Ensure External Secrets can reach the Vault service

### External Secrets Configuration Issues

- **Incorrect ClusterSecretStore path**: The `path` field in ClusterSecretStore must match the Vault mount name
  - Correct: `path: "operationtimecapsule"`
  - Wrong: `path: "secret"`
- **Wrong External Secret key paths**: Key paths should NOT include the mount prefix
  - Correct: `key: smb/general-media-r`
  - Wrong: `key: operationtimecapsule/smb/general-media-r`
- **Vault policy permissions**: Ensure the policy includes both `data/*` and `metadata/*` paths:
  ```bash
  path "operationtimecapsule/data/*" {
    capabilities = ["read", "list"]
  }
  path "operationtimecapsule/metadata/*" {
    capabilities = ["read", "list"]
  }
  path "zeldas-letter/data/*" {
    capabilities = ["read", "list"]
  }
  path "zeldas-letter/metadata/*" {
    capabilities = ["read", "list"]
  }
  path "precisionplanit/data/*" {
    capabilities = ["read", "list"]
  }
  path "precisionplanit/metadata/*" {
    capabilities = ["read", "list"]
  }
  ```

### Pod and Container Issues

- **ImagePullBackOff with short names**: Container images must use fully qualified registry paths
  - Correct: `docker.io/plexinc/pms-docker:latest`
  - Wrong: `plexinc/pms-docker:latest`
- **Expired Plex claim tokens**: Plex claim tokens expire in ~4 minutes. To refresh:
  1. Update token in Vault
  2. Delete External Secret: `kubectl delete externalsecret plex-claim -n namespace`
  3. Delete existing secret: `kubectl delete secret plex-claim -n namespace`
  4. Reconcile: `flux reconcile kustomization apps`
  5. Restart pod: `kubectl delete pod plex-0 -n namespace`

### Storage and PVC Issues

- **Namespace migration for Ceph storage**: When moving from one namespace to another, existing PVs may reference old namespace secrets
  - Solution: Delete PVCs to force recreation with correct namespace references
  - Check PV details: `kubectl get pv pv-name -o yaml | grep nodeStageSecretRef -A5`
- **SMB mount permission denied**: Usually indicates incorrect credentials or credential order
  - Verify credentials: `kubectl get secret smb-secret -o yaml`
  - Check if username/password are swapped in Vault
  - Restart pods after credential fixes

## Verification

Check that the ClusterSecretStore is ready:

```bash
kubectl get clustersecretstore vault-backend
```

The status should show "Ready: True" when properly configured.

Verify that ExternalSecrets are working:

```bash
kubectl get externalsecrets -n operationtimecapsule
```

Both should show "STATUS: SecretSynced" and "READY: True".

Check that secrets were created:

```bash
kubectl get secrets -n operationtimecapsule
```

You should see `plex-claim` and `plex-smb-secret` secrets with proper data.

## Success Criteria

When everything is working correctly, you should see:

1. `vault read auth/kubernetes/config` shows `token_reviewer_jwt_set: true`
2. `kubectl get clustersecretstore vault-backend` shows `Ready: True`
3. `kubectl get externalsecrets -A` shows all External Secrets as `SecretSynced: True`
4. Applications can successfully mount and use the secrets

## Quick Reference Commands

### Force External Secret Refresh
```bash
# Delete and recreate External Secret
kubectl delete externalsecret secret-name -n namespace
kubectl delete secret secret-name -n namespace  # if it exists
flux reconcile kustomization apps
```

### Check External Secrets Status
```bash
# Check all External Secrets
kubectl get externalsecrets -A

# Check specific External Secret details
kubectl describe externalsecret secret-name -n namespace

# Check ClusterSecretStore status
kubectl get clustersecretstore vault-backend
```

### Vault Authentication Testing
```bash
# Get ServiceAccount token
SA_TOKEN=$(kubectl get secret external-secrets-vault-token -n prplanit-atlas -o jsonpath='{.data.token}' | base64 -d)

# Test Kubernetes auth
kubectl exec -n prplanit-atlas vault-0 -- sh -c \
  "VAULT_TOKEN=\$(VAULT_TOKEN=root-token vault write -address=http://127.0.0.1:8200 -field=token auth/kubernetes/login role=external-secrets jwt=\"$SA_TOKEN\") && \
   vault kv get -address=http://127.0.0.1:8200 operationtimecapsule/path/to/secret"
```

### Force PVC Recreation
```bash
# Delete PVC (will also delete associated PV if using Delete reclaim policy)
kubectl delete pvc pvc-name -n namespace

# Check PV details for namespace references
kubectl get pv | grep pvc-name
kubectl get pv pv-name -o yaml | grep -A5 nodeStageSecretRef
```