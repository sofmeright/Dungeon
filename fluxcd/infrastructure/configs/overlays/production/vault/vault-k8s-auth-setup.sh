#!/bin/bash
# Script to configure Vault's Kubernetes authentication
# This needs to be run after Vault is unsealed

VAULT_POD=$(kubectl get pod -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
VAULT_SA_NAME="external-secrets-vault"
VAULT_NAMESPACE="prplanit-system"

# Get the JWT token and CA cert from the ServiceAccount
SA_JWT_TOKEN=$(kubectl get secret -n ${VAULT_NAMESPACE} $(kubectl get sa -n ${VAULT_NAMESPACE} ${VAULT_SA_NAME} -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 -d)
K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
K8S_CA_CERT=$(kubectl get secret -n ${VAULT_NAMESPACE} $(kubectl get sa -n ${VAULT_NAMESPACE} ${VAULT_SA_NAME} -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.ca\.crt}' | base64 -d)

# Enable Kubernetes auth in Vault
kubectl exec -n vault ${VAULT_POD} -- vault auth enable kubernetes

# Configure Kubernetes auth
kubectl exec -n vault ${VAULT_POD} -- vault write auth/kubernetes/config \
    token_reviewer_jwt="${SA_JWT_TOKEN}" \
    kubernetes_host="${K8S_HOST}" \
    kubernetes_ca_cert="${K8S_CA_CERT}" \
    disable_issuer_verification=true

# Create a policy for external-secrets
kubectl exec -n vault ${VAULT_POD} -- vault policy write external-secrets - <<EOF
path "secret/*" {
  capabilities = ["read", "list"]
}
path "operationtimecapsule/*" {
  capabilities = ["read", "list"]
}
EOF

# Create role for external-secrets
kubectl exec -n vault ${VAULT_POD} -- vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=${VAULT_SA_NAME} \
    bound_service_account_namespaces=${VAULT_NAMESPACE} \
    policies=external-secrets \
    ttl=24h

echo "Vault Kubernetes authentication configured successfully!"