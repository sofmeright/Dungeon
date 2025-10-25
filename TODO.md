# TODO

## PVC Naming Standard Alignment

CLAUDE.md specifies PVC naming pattern for StatefulSets: `<namespace>-<app>-<purpose>-<app>-<ordinal>`
(Note: Due to StatefulSet behavior, app name appears twice: once in volumeClaimTemplate name, once from StatefulSet name)

**Completed migrations:**
- ✅ Plex: `temple-of-time-plex-config-plex-0`, `temple-of-time-plex-transcode-plex-0`
- ✅ Jellyfin: `temple-of-time-jellyfin-config-jellyfin-0`, `temple-of-time-jellyfin-cache-jellyfin-0`
- ✅ Linkwarden: `temple-of-time-linkwarden-data-linkwarden-0`, `temple-of-time-linkwarden-postgres-linkwarden-postgres-0`, `temple-of-time-linkwarden-meilisearch-linkwarden-meilisearch-0`
- ✅ Mealie: `temple-of-time-mealie-data-mealie-0`, `temple-of-time-mealie-postgres-mealie-postgres-0`

**Remaining non-compliant StatefulSet PVCs:**

### temple-of-time namespace:
- [ ] PhotoPrism MariaDB: `database-photoprism-mariadb-0` → `temple-of-time-photoprism-mariadb-database-mariadb-0`
- [ ] PhotoPrism: `storage-photoprism-0` → `temple-of-time-photoprism-storage-photoprism-0`
- [ ] Immich (old PVCs - need cleanup): `library-immich-0`, `model-cache-immich-0`, `postgres-immich-0`

### compass namespace:
- [ ] AdGuard: `adguard-conf-adguard-0` → `compass-adguard-conf-adguard-0`
- [ ] AdGuard: `adguard-data-adguard-0` → `compass-adguard-data-adguard-0`

### gorons-bracelet namespace:
- [ ] Ceph RGW: `rgw-data-ceph-rgw-0` → `gorons-bracelet-ceph-rgw-data-ceph-rgw-0`
- [ ] Ceph RGW: `rgw-data-ceph-rgw-1` → `gorons-bracelet-ceph-rgw-data-ceph-rgw-1`

### shooting-gallery namespace:
- [ ] Minecraft: `data-minecraft-0` → `shooting-gallery-minecraft-data-minecraft-0`

### lens-of-truth namespace:
- [ ] Shinobi: `app-shinobi-0` → `lens-of-truth-shinobi-app-shinobi-0`
- [ ] Shinobi: `mysql-shinobi-0` → `lens-of-truth-shinobi-mysql-shinobi-0`
- [ ] Shinobi: `streams-shinobi-0` → `lens-of-truth-shinobi-streams-shinobi-0`
- [ ] Wazuh Dashboard: `dashboard-data-wazuh-dashboard-0` → `lens-of-truth-wazuh-dashboard-data-wazuh-dashboard-0`
- [ ] Wazuh Indexer: `wazuh-indexer-data-wazuh-indexer-0` → `lens-of-truth-wazuh-indexer-data-wazuh-indexer-0`
- [ ] Wazuh Manager: `wazuh-manager-data-wazuh-manager-0` → `lens-of-truth-wazuh-manager-data-wazuh-manager-0`

### tingle-tuner namespace:
- [ ] Ollama: `data-ollama-0` → `tingle-tuner-ollama-data-ollama-0`
- [ ] LibreTranslate: `models-libretranslate-0` → `tingle-tuner-libretranslate-models-libretranslate-0`

### zeldas-lullaby namespace:
- [ ] Vault: `vault-data` → `zeldas-lullaby-vault-data-vault-0` (if StatefulSet)
- [ ] Zitadel: `zitadel-postgres-data` → `zeldas-lullaby-zitadel-postgres-data-zitadel-postgres-0` (if StatefulSet)

**Migration process (learned from Jellyfin/Plex migrations):**
1. Update volumeClaimTemplate names in StatefulSet patch to include namespace prefix
2. Scale down StatefulSet to 0 replicas
3. Commit changes and let FluxCD reconcile
4. Create recovery PVCs to mount old PVs
5. Use rsync with --delete flag to copy all data to new PVCs
6. Scale up StatefulSet and verify functionality
7. Clean up old PVCs, PVs, and RBD images from Ceph

**Note:** Each migration requires app downtime. Plan migrations during maintenance windows.

## Application Deployment - Final Stretch

### Remaining Applications to Template and Deploy to Kubernetes
- [x] calcom (Cal.com) - Scheduling platform from Moor (2 containers: app + studio) - COMPLETED
- [x] opnform - Form builder platform from Moor (7 containers: api, scheduler, worker, client, db, ingress, redis) - hyrule-castle namespace - COMPLETED
- [x] crowdsec - Security/IDS platform from Lighthouse (2 containers: crowdsec + dashboard)
- [ ] anirra - Custom arr app from Pirates-WDDA
- [ ] matrix-synapse - Matrix homeserver (federated chat)
- [ ] mastodon - Federated social media platform
- [x] kimai - Time tracking application (https://github.com/kimai/kimai) - temple-of-time namespace - COMPLETED
- [x] mazanoke - Image converting app (https://github.com/civilblur/mazanoke) - tingle-tuner namespace - COMPLETED

**Status:** Final 3 applications remaining out of 100+ total applications inventoried across all Portainer endpoints.

**Applications that would be nice to add to the stack:**
- [ ] tinkerbell (Machine deployment automations)
- [ ] kubevirt (hypervisor)
- [ ] rook-ceph ~ Could potentially migrate PVE Ceph to K8s with BGP loadbalancing & disk passthrough we would lose nothing...
- [ ] vyOS ~ could extend k8s to handling routing and setup something truly resiliant and robust as compared to pfsense.

**Large stacks to migrate** (not yet deployed to K8s):
- [ ] ARK servers (6 instances) - Game servers on Jabu-Jabu
- [ ] Minecraft servers (2 instances) - Game servers on Jabu-Jabu

**Custom container images needed:**
- [ ] Proxmox Backup Server - No decent official container image available, will need to create custom image

**Custom landing pages / static sites to containerize:**
- [ ] sofmeright.com - Personal landing page
- [ ] precisionplanit.com - Business landing page
- [ ] yesimvegan.com - Vegan resources landing page
- [ ] astralfocal.com - Landing page
- [ ] homelabhelpdesk.com - Homelab resources landing page

## Applications Requiring Further Review

**Applications that cannot be deployed to Kubernetes in current form:**

### Nextcloud AIO (All-in-One)
**Status:** Architecture incompatible with Kubernetes
**Reason:** Nextcloud AIO is designed specifically for Docker and Docker Compose with tight coupling to:
- Docker socket access for managing its own containers
- Self-managed backup system requiring specific volume structure
- Master container pattern that dynamically creates/destroys other containers
- Hardcoded container names that cannot be changed without breaking functionality
- Reliance on Docker-specific networking and volume behaviors

**Current deployment:** Running on Docker host at `10.30.1.123` (Moor)

**Why standard Nextcloud Helm charts won't work:**
- No support for Nextcloud apps/plugins (Collabora, OnlyOffice, Talk, etc.)
- Missing integrated components that AIO provides (imaginary, fulltextsearch, notify_push)
- Requires manual assembly of disparate components with complex configuration
- No equivalent to AIO's automated backup/restore system
- Would lose significant functionality compared to current AIO deployment

**Decision:** Keep running on dedicated Docker host - AIO provides superior experience and functionality

### Mailcow
**Status:** Architecture incompatible with Kubernetes
**Reason:** Mailcow (18 containers) is designed specifically for Docker and Docker Compose with similar issues to Nextcloud AIO:
- Docker socket access for container management and monitoring
- Complex inter-container dependencies with hardcoded names and network aliases
- Integrated watchdog/monitoring system managing container lifecycle
- Email infrastructure requires stable networking - Kubernetes pod churn would break delivery
- Self-managed backup system tied to Docker volume structure

**Current deployment:** Production email stack on dedicated Docker host

**Decision:** Keep running on dedicated Docker host - email infrastructure is too critical to risk migration

## Infrastructure Modernization

### Migrate from Traefik to Cilium Gateway API
**Status:** Planned migration
**Current state:** Traefik deployed as ingress controller
**Target state:** Cilium Gateway API for unified networking stack

**Benefits of migration:**
- Unified CNI + LoadBalancer + Ingress in single component (Cilium)
- eBPF-powered performance with lower latency and higher throughput
- Reduced resource usage (no separate ingress controller pods)
- Native integration with Cilium network policies
- Simpler architecture with fewer moving parts
- Future-proof eBPF-based networking

**Migration tasks:**
- [ ] Deploy Cilium Gateway API infrastructure (GatewayClass, Gateways)
- [ ] Create three Gateways with IP-based isolation:
  - [ ] xylem-gateway (172.22.30.69) - Internal-only services (*.pcfae.com)
  - [ ] phloem-gateway (172.22.30.70) - Personal/public services (*.sofmeright.com, *.arbitorium.com, *.yesimvegan.com)
  - [ ] cell-membrane-gateway (172.22.30.71) - Business/work services (*.precisionplanit.com, *.prplanit.com, *.optcp.com, *.ipleek.com, *.uni2.cc)
- [ ] Configure TLS certificates for each Gateway (cert-manager + Let's Encrypt)
- [ ] Migrate HTTPRoutes from Traefik IngressRoute to Gateway API HTTPRoute
- [ ] Test traffic routing and TLS termination
- [ ] Update pfSense port forwarding rules for Gateway IPs
- [ ] Remove Traefik deployment after successful migration
- [ ] Clean up old Traefik resources and configs

**Protocol support verified:**
- ✅ HTTP/HTTPS - Full HTTPRoute support
- ✅ gRPC - GRPCRoute supported
- ✅ TCP/UDP - Supported via separate Gateways (L4 vs L7 separation)

**Note:** Migration can be done incrementally - keep Traefik running while deploying Cilium Gateway, migrate routes one gateway at a time, then remove Traefik when complete.
