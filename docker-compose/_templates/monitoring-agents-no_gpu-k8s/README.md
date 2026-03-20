# monitoring-agents-no_gpu-k8s

Replaces `monitoring-agents-no_gpu` (Loki Docker log driver → lighthouse) with
Alloy-based log/metric shipping directly to K8s Loki + VictoriaMetrics.

No Loki Docker driver. All containers use `json-file` logging. Alloy reads
from the Docker socket and pushes to K8s over HTTPS with basic auth.

## Files to create at deploy time

Copy `docker-compose.yaml` and `alloy-config.alloy` to the host, then create:

```
_hostname.env            # HOSTNAME=<this-host>
alloy-loki_secret.env    # LOKI_AUTH_USERNAME=<BASIC_AUTH_USER from Vault apps/loki>
alloy-vm_secret.env      # VM_AUTH_USERNAME=<BASIC_AUTH_USER from Vault apps/victoria-metrics>
beszel-agent.env         # PORT=45876
beszel-agent_secret.env  # KEY=ssh-ed25519 <public-key-from-beszel-hub>
cadvisor.env             # (empty or CADVISOR_HEALTHCHECK_URL=http://localhost:8098/healthz)
watchtower.env           # WATCHTOWER_NOTIFICATION_URL=https://ntfy.pcfae.com/watchtower
watchtower-secret.env    # WATCHTOWER_NOTIFICATION_TOKEN=tk_...
secrets/loki_password    # plaintext BASIC_AUTH_PASS from Vault apps/loki
secrets/vm_password      # plaintext BASIC_AUTH_PASS from Vault apps/victoria-metrics
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
