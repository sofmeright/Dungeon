# Resource Tuning - tingle-tuner namespace

Tuned 2026-01-10. Formula: request ~1.2x actual, limit ~5x request (with exceptions for startup/jobs).

| Namespace | App | CPU Actual | CPU Request | CPU Limit | Mem Actual | Mem Request | Mem Limit | Notes |
|-----------|-----|------------|-------------|-----------|------------|-------------|-----------|-------|
| tingle-tuner | code-server | 1-47m | 2m | 50m | 17Mi | 256Mi | 1Gi | Spikes during active use |
| tingle-tuner | it-tools (x3) | 1m | 2m | 10m | 13Mi | 32Mi | 128Mi | |
| tingle-tuner | searxng (x3) | 1-2m | 3m | 25m | 200Mi | 256Mi | 512Mi | |
| tingle-tuner | searxng-redis (x3) | 3-5m | 6m | 10m | 3-6Mi | 32Mi | 128Mi | |
| tingle-tuner | draw-io | 11-15m | 15m | 100m | 81Mi | 96Mi | 128Mi | Needs 100m for RSA cert gen on startup (~99s at 100m, ~218s at 50m) |
| tingle-tuner | hrconvert2 | 1m | 2m | 10m | 9Mi | 64Mi | 256Mi | |
| tingle-tuner | google-webfonts-helper | 1m | 2m | 10m | 51Mi | 64Mi | 128Mi | |
| tingle-tuner | convertx | 1m | 2m | 10m | 63Mi | 64Mi | 256Mi | |
| tingle-tuner | neko-vpn/gluetun | 1m | 2m | 10m | 82Mi | 100Mi | 256Mi | VPN container |
| tingle-tuner | neko-vpn/neko | 85-92m | 102m | 500m | 488Mi | 586Mi | 1Gi | Browser workload, needs headroom |
