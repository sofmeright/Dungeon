# Resource Tuning

Tuned 2026-01-10. Formula: request ~1.2x actual (4Mi multiples for mem), limit ~20% over request.

## tingle-tuner namespace

| Namespace | App | CPU Actual | CPU Request | CPU Limit | Mem Actual | Mem Request | Mem Limit | Notes |
|-----------|-----|------------|-------------|-----------|------------|-------------|-----------|-------|
| tingle-tuner | code-server | 1-47m | 2m | 50m | 44Mi | 24Mi | 48Mi | CPU spikes during active use |
| tingle-tuner | it-tools (x3) | 1m | 2m | 10m | 13Mi | 16Mi | 20Mi | |
| tingle-tuner | searxng (x3) | 1-2m | 150m | 200m | 200Mi | 256Mi | 512Mi | Needs 150m+ CPU for granian startup; 150m unstable, 140m fails |
| tingle-tuner | searxng-redis (x3) | 3-5m | 6m | 10m | 3-6Mi | 32Mi | 128Mi | |
| tingle-tuner | draw-io | 11-15m | 15m | 100m | 81Mi | 84Mi | 104Mi | Needs 100m CPU for RSA cert gen on startup (~99s at 100m, ~218s at 50m) |
| tingle-tuner | hrconvert2 | 1m | 2m | 10m | 9Mi | 12Mi | 16Mi | |
| tingle-tuner | google-webfonts-helper | 1m | 2m | 10m | 51Mi | 52Mi | 64Mi | |
| tingle-tuner | convertx | 1m | 2m | 10m | 24Mi | 64Mi | 96Mi | OOMKilled at 80Mi |
| tingle-tuner | neko-vpn/gluetun | 1m | 2m | 10m | 82Mi | 100Mi | 152Mi | VPN container |
| tingle-tuner | neko-vpn/neko | 85-92m | 102m | 500m | 488Mi | 586Mi | 1Gi | Browser workload, needs headroom |

## zeldas-lullaby namespace

| Namespace | App | CPU Actual | CPU Request | CPU Limit | Mem Actual | Mem Request | Mem Limit | Notes |
|-----------|-----|------------|-------------|-----------|------------|-------------|-----------|-------|
| zeldas-lullaby | netbird-coturn | 1m | 6m | 100m | 1Mi | 8Mi | 128Mi | TURN relay needs headroom for actual traffic |
| zeldas-lullaby | netbird-dashboard | 1m | 2m | 10m | 30Mi | 36Mi | 48Mi | |
| zeldas-lullaby | netbird-management | 1m | 2m | 10m | 36Mi | 40Mi | 48Mi | |
| zeldas-lullaby | netbird-relay | 1m | 2m | 10m | 2Mi | 4Mi | 8Mi | |
| zeldas-lullaby | netbird-signal | 1m | 2m | 10m | 2Mi | 4Mi | 8Mi | |
| zeldas-lullaby | zitadel | 52m | 60m | 200m | 97Mi | 128Mi | 256Mi | |
| zeldas-lullaby | zitadel-login-v2 | 1m | 2m | 50m | 85Mi | 100Mi | 128Mi | |
| zeldas-lullaby | zitadel-postgres | 30m | 35m | 100m | 49Mi | 64Mi | 128Mi | |
| zeldas-lullaby | vaultwarden | 1m | 2m | 50m | 21Mi | 24Mi | 32Mi | |
| zeldas-lullaby | vaultwarden-postgres | 20m | 25m | 100m | 14Mi | 24Mi | 32Mi | |
| zeldas-lullaby | vault | 66m | 70m | 150m | 138Mi | 144Mi | 256Mi | |
| zeldas-lullaby | vault-bank-vaults | 1m | 2m | 20m | 45Mi | 64Mi | 128Mi | |
| zeldas-lullaby | vault-prometheus-exporter | 1m | 2m | 10m | 13Mi | 16Mi | 32Mi | |
| zeldas-lullaby | netbox | 2m | 5m | 100m | 445Mi | 512Mi | 768Mi | |
| zeldas-lullaby | netbox-postgres | 1m | 2m | 50m | 15Mi | 24Mi | 32Mi | |
| zeldas-lullaby | netbox-redis | 15m | 20m | 50m | 3Mi | 8Mi | 16Mi | |
| zeldas-lullaby | oauth2-proxy | 1m | 2m | 10m | 11Mi | 12Mi | 24Mi | |
| zeldas-lullaby | semaphore | 1m | 2m | 100m | 11Mi | 32Mi | 64Mi | |
| zeldas-lullaby | semaphore-postgres | 1m | 2m | 20m | 14Mi | 24Mi | 64Mi | |
| zeldas-lullaby | twofauth | 1m | 2m | 10m | 11Mi | 16Mi | 24Mi | |
| zeldas-lullaby | bank-vaults-operator | 2m | 5m | 50m | 77Mi | 96Mi | 128Mi | |
