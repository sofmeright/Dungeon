# monitoring-agents-no_gpu-k8s

Replaces `monitoring-agents-no_gpu` (Loki Docker log driver → lighthouse) with
Alloy-based log/metric shipping directly to K8s Loki + VictoriaMetrics.

No Loki Docker driver. All containers use `json-file` logging. Alloy reads
from the Docker socket and pushes to K8s over HTTPS with basic auth.

## Files to create at deploy time

Deploy `docker-compose.yaml` (Alloy config is embedded inline), then create:

```
_hostname.env              # HOSTNAME=<this-host>
alloy-secret.env           # LOKI_AUTH_USERNAME=... VM_AUTH_USERNAME=...
beszel-agent-secret.env    # KEY=ssh-ed25519 <public-key-from-beszel-hub> PORT=45876
watchtower-secret.env      # WATCHTOWER_NOTIFICATION_URL=... WATCHTOWER_NOTIFICATION_TOKEN=...
secrets/loki-password                # plaintext BASIC_AUTH_PASS from Vault apps/loki
secrets/victoria-metrics-password    # plaintext BASIC_AUTH_PASS from Vault apps/victoria-metrics
```

## Vault secrets

All secrets in `zeldas-letter` engine via ClusterSecretStore `vault-zeldas-letter`.

### `zeldas-letter/apps/loki`

Add gateway auth keys (S3 creds are at `rgw/loki` separately):

- `BASIC_AUTH_USER` — username for external log ingest
- `BASIC_AUTH_PASS` — generated password
- `BASIC_AUTH_HTPASS` — output of `htpasswd -nbB <username> <password>`

### `zeldas-letter/apps/victoria-metrics`

- `BASIC_AUTH_USER` — username for external metric ingest
- `BASIC_AUTH_PASS` — generated password
