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
- [ ] calcom (Cal.com) - Scheduling platform from Moor (2 containers: app + studio)
- [ ] opnform - Form builder platform from Moor (7 containers: api, scheduler, worker, client, db, ingress, redis)
- [ ] crowdsec - Security/IDS platform from Lighthouse (2 containers: crowdsec + dashboard)
- [ ] anirra - Custom arr app from Pirates-WDDA
- [ ] matrix-synapse - Matrix homeserver (federated chat)
- [ ] mastodon - Federated social media platform
- [ ] kimai - Time tracking application (https://github.com/kimai/kimai) - tingle-tuner namespace
- [ ] mazanoke - Bookmark manager (https://github.com/civilblur/mazanoke) - tingle-tuner namespace

**Status:** Final 8 applications remaining out of 100+ total applications inventoried across all Portainer endpoints.

**Large stacks to migrate** (not yet deployed to K8s):
- [ ] Mailcow (18 containers) - Email stack, production critical
- [ ] Nextcloud AIO (14 containers) - File sharing, large stack
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
