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

1. Verify the ServiceAccount exists and has the token secret
2. Check that the ClusterRole binding exists
3. Ensure the Vault role name matches exactly
4. Verify the bound ServiceAccount names and namespaces in the Vault role
5. Check that the Kubernetes auth method is properly configured with CA cert and issuer

### Testing Authentication

You can test authentication manually:

```bash
# Get the ServiceAccount token
SA_TOKEN=$(kubectl get secret external-secrets-vault-token -n prplanit-atlas -o jsonpath='{.data.token}' | base64 -d)

# Test authentication with Vault
vault write auth/kubernetes/login role=external-secrets jwt="${SA_TOKEN}"
```

### Common Issues

- **Wrong ServiceAccount**: Ensure the serviceAccountRef in the ClusterSecretStore matches the actual ServiceAccount
- **Missing ClusterRole binding**: The `system:auth-delegator` ClusterRole is required
- **Vault configuration**: CA cert and issuer must be properly configured
- **Network connectivity**: Ensure External Secrets can reach the Vault service

## Verification

Check that the ClusterSecretStore is ready:

```bash
kubectl get clustersecretstore vault-backend
```

The status should show "Ready: True" when properly configured.