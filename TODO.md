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
- [ ] matrix-synapse - Matrix homeserver (federated chat)
- [ ] mastodon - Federated social media platform

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

### Standardize Ceph CSI Provisioner Naming
**Status:** Inconsistent naming between RBD and CephFS provisioners
**Current state:**
- RBD StorageClasses use `rbd.csi.ceph.com` provisioner (generic upstream naming)
- CephFS StorageClasses use `gorons-bracelet.cephfs.csi.ceph.com` provisioner (cluster-specific naming)

**Target state:** Both provisioners should follow the same naming pattern
- Option 1: Rename RBD to `gorons-bracelet.rbd.csi.ceph.com` (matches CephFS pattern)
- Option 2: Rename CephFS to `rbd.csi.ceph.com` pattern (but CephFS is already deployed as cluster-specific)

**Recommended approach:** Rename RBD provisioner to match CephFS cluster-specific naming

**Migration tasks:**
- [ ] Update RBD Driver CRD name from `gorons-bracelet.rbd.csi.ceph.com` to match naming pattern
- [ ] Update all RBD StorageClasses to use new provisioner name
- [ ] Migrate existing PVCs using old provisioner name to new provisioner (may require PVC recreation)
- [ ] Update application manifests referencing old StorageClass names
- [ ] Test dynamic provisioning with new RBD provisioner name
- [ ] Clean up old provisioner resources after migration

**Note:** This will cause downtime for applications using RBD PVCs during migration. Plan carefully.

## Cilium cluster-pool IPAM Migration

### Overview
Migrate from `ipam: kubernetes` to `ipam: cluster-pool` to enable static pod IP assignments and improve network segmentation through IP-based tiering.

### Primary Goal
Enable static pod IP for CrowdSec cloudflare-bouncer to prevent duplicate LAPI registrations.

**Problem:** CrowdSec LAPI tracks bouncers by source IP. Each pod restart = new IP = duplicate bouncer registration.

**Solution:** Static pod IP annotation (requires cluster-pool IPAM mode).

### Planned IP Segmentation

#### IPv4 Pod CIDR: 192.168.144.0/20 (4096 IPs total)

**Tier 0: Core Infrastructure** - `192.168.144.0/22` (1024 IPs)
- Namespaces: `kube-system`, `flux-system`, `gorons-bracelet`
- Purpose: K8s control plane, storage operators, CSI drivers, core CNI

**Tier 1: Security & Administrative** - `192.168.148.0/23` (512 IPs)
- Namespaces: `zeldas-lullaby`, `lens-of-truth`, `wallmaster`
- Purpose: Vault, Zitadel, External Secrets, CrowdSec, Wazuh, IDS/IPS, bot protection

**Tier 2: Monitoring & Observability** - `192.168.150.0/24` (256 IPs)
- Namespaces: `gossip-stone`
- Purpose: Prometheus, Grafana, Loki, Alloy, Thanos

**Tier 3: Networking Services** - `192.168.151.0/24` (256 IPs)
- Namespaces: `compass`, `king-of-red-lions`
- Purpose: DNS (AdGuard), NTP (Chrony), Traefik, cert-manager, Gateway API

**Tier 4: Business/Work - Tenant A** - `192.168.152.0/22` (1024 IPs)
- Namespaces: `hyrule-castle`
- Purpose: GitLab, ERPNext, Dolibarr, InvoiceNinja, business applications

**Tier 5: Media & Content** - `192.168.156.0/23` (512 IPs)
- Namespaces: `temple-of-time`, `pedestal-of-time`
- Purpose: Plex, Jellyfin, Immich, Calibre-Web, Mealie, content management

**Tier 6: General Services** - `192.168.158.0/23` (512 IPs)
- Namespaces: `lost-woods`, `tingle-tuner`, `kokiri-forest`, `delivery-bag`, `fairy-bottle`
- Purpose: Dashboards, IT tools, file browsers, notifications, backups (Velero)

**Tier 7: Isolated/VPN-routed** - `192.168.160.0/24` (256 IPs)
- Namespaces: `swift-sail`
- Purpose: Arr apps (Prowlarr, Radarr, Sonarr, etc.) through Gluetun VPN

**Tier 8: Game Servers** - `192.168.161.0/24` (256 IPs)
- Namespaces: `shooting-gallery`
- Purpose: Minecraft, ARK, Pelican Panel, game hosting

**Tier 9: Remote Access** - `192.168.162.0/24` (256 IPs)
- Namespaces: `hookshot`
- Purpose: Guacamole, TacticalRMM, MeshCentral

**Static Infrastructure Assignments** - `192.168.163.0/24` (256 IPs)
- Purpose: Reserved pool for static pod IP annotations
- Examples: CrowdSec cloudflare-bouncer (192.168.163.200)

#### IPv6 Pod CIDR: fc00:f1:d759:3053:a573::/64

Mirrors IPv4 tier structure with equivalent subnet sizes:

- **Tier 0**: `fc00:f1:d759:3053:a573:0::/67` - Core Infrastructure
- **Tier 1**: `fc00:f1:d759:3053:a573:2000::/67` - Security & Admin
- **Tier 2**: `fc00:f1:d759:3053:a573:4000::/68` - Monitoring
- **Tier 3**: `fc00:f1:d759:3053:a573:5000::/68` - Networking Services
- **Tier 4**: `fc00:f1:d759:3053:a573:6000::/66` - Business/Work
- **Tier 5**: `fc00:f1:d759:3053:a573:a000::/67` - Media & Content
- **Tier 6**: `fc00:f1:d759:3053:a573:c000::/67` - General Services
- **Tier 7**: `fc00:f1:d759:3053:a573:e000::/68` - Isolated/VPN
- **Tier 8**: `fc00:f1:d759:3053:a573:e100::/68` - Game Servers
- **Tier 9**: `fc00:f1:d759:3053:a573:e200::/68` - Remote Access
- **Static**: `fc00:f1:d759:3053:a573:e300::/68` - Static Infrastructure

### Implementation

**File**: `/srv/dungeon/fluxcd/infrastructure/controllers/base/cilium/helmrelease.yaml`

Change from:
```yaml
ipam:
  mode: kubernetes
```

To:
```yaml
ipam:
  mode: cluster-pool
  operator:
    clusterPoolIPv4PodCIDRList:
      - "192.168.144.0/22"    # Tier 0: Infrastructure
      - "192.168.148.0/23"    # Tier 1: Security & Admin
      - "192.168.150.0/24"    # Tier 2: Monitoring
      - "192.168.151.0/24"    # Tier 3: Networking
      - "192.168.152.0/22"    # Tier 4: Business/Work
      - "192.168.156.0/23"    # Tier 5: Media & Content
      - "192.168.158.0/23"    # Tier 6: General Services
      - "192.168.160.0/24"    # Tier 7: Isolated/VPN
      - "192.168.161.0/24"    # Tier 8: Game Servers
      - "192.168.162.0/24"    # Tier 9: Remote Access
      - "192.168.163.0/24"    # Static Infrastructure
    clusterPoolIPv6PodCIDRList:
      - "fc00:f1:d759:3053:a573:0::/67"
      - "fc00:f1:d759:3053:a573:2000::/67"
      - "fc00:f1:d759:3053:a573:4000::/68"
      - "fc00:f1:d759:3053:a573:5000::/68"
      - "fc00:f1:d759:3053:a573:6000::/66"
      - "fc00:f1:d759:3053:a573:a000::/67"
      - "fc00:f1:d759:3053:a573:c000::/67"
      - "fc00:f1:d759:3053:a573:e000::/68"
      - "fc00:f1:d759:3053:a573:e100::/68"
      - "fc00:f1:d759:3053:a573:e200::/68"
      - "fc00:f1:d759:3053:a573:e300::/68"
```

**Static IP Annotation** (already applied to CrowdSec cloudflare-bouncer):
```yaml
# File: fluxcd/infrastructure/controllers/overlays/production/crowdsec/statefulset-cloudflare-bouncer-patch.yaml
spec:
  template:
    metadata:
      annotations:
        ipam.cilium.io/ip-address: "192.168.163.200"
```

### Migration Impact

**Estimated Downtime**: 5-15 minutes rolling disruption

**What Changes**:
- All 321 pods get new IPs from cluster-pool as Cilium DaemonSet rolls out
- Pod IPs reassigned within same overall CIDR (192.168.144.0/20)
- Connections drop and reconnect as pods restart

**What Stays Stable**:
- Service ClusterIPs (10.144.0.0/12) - unchanged
- LoadBalancer IPs (172.22.30.0/24) - unchanged
- Node IPs (172.22.144.x) - unchanged
- BGP routes - entire /20 still advertised

**Risk Assessment**: Medium
- Pods communicate via Services/DNS (not direct pod IPs) - minimal impact
- Network policies use label selectors (not IPs) - no changes needed
- Potential issues: Long-lived connections, WebSockets may drop temporarily

### Benefits

- **Static pod IPs**: Annotations enable permanent IP assignment (solves CrowdSec bouncer issue)
- **Network segmentation**: IP-based tiers enable clearer security boundaries
- **Multi-tenancy ready**: IP isolation supports future tenant segregation
- **Advanced features**: Unlocks per-namespace pools, IP reservation, multi-cluster IPAM

## GPU Infrastructure

### Kernel Version Pinning for dungeon-chest-004

**Status:** Active - Kernel pinned at 6.8.0-86-generic

**Node:** dungeon-chest-004 (172.22.144.173)

**Reason:**
- NVIDIA GPU Operator requires precompiled driver containers for Secure Boot compatibility
- Current kernel 6.8.0-86-generic has available precompiled driver: `nvcr.io/nvidia/driver:580-6.8.0-86-generic-ubuntu24.04`
- Newer kernel 6.8.0-87-generic does NOT have precompiled driver available yet (as of 2025-11-10)
- Runtime driver compilation is incompatible with Secure Boot (requires MOK key enrollment - unacceptable for production)

**Held Packages:**
```bash
linux-image-6.8.0-86-generic
linux-headers-6.8.0-86-generic
linux-modules-6.8.0-86-generic
linux-modules-extra-6.8.0-86-generic
linux-image-generic
linux-headers-generic
```

**Upgrade Conditions:**
- [ ] Wait for NVIDIA to publish precompiled driver container for kernel 6.8.0-87-generic or newer
- [ ] Verify new driver tag exists in NGC catalog before upgrading kernel
- [ ] Test GPU Operator with new kernel version before holding new kernel

**How to Check for New Precompiled Drivers:**

Visit NGC catalog: https://catalog.ngc.nvidia.com/orgs/nvidia/containers/driver

Look for tags matching pattern: `580-<kernel-version>-ubuntu24.04`
- Example current working version: `580-6.8.0-86-generic-ubuntu24.04`
- Example future version: `580-6.8.0-87-generic-ubuntu24.04`

**How to Upgrade When Available:**

1. Verify precompiled driver exists in NGC catalog for target kernel version
2. SSH to dungeon-chest-004 and unhold kernel packages:
   ```bash
   ssh dungeon-chest-004 "sudo apt-mark unhold linux-image-generic linux-headers-generic linux-image-6.8.0-86-generic linux-headers-6.8.0-86-generic linux-modules-6.8.0-86-generic linux-modules-extra-6.8.0-86-generic"
   ```
3. Upgrade system packages:
   ```bash
   ssh dungeon-chest-004 "sudo apt update && sudo apt upgrade -y"
   ```
4. Reboot node to load new kernel:
   ```bash
   ssh dungeon-chest-004 "sudo reboot"
   ```
5. Wait for node to come back online and verify new kernel:
   ```bash
   ssh dungeon-chest-004 "uname -r"
   ```
6. Verify GPU Operator driver pod starts successfully:
   ```bash
   kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset
   kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=50
   ```
7. Verify GPU is available in Kubernetes:
   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.'nvidia\.com/gpu'
   ```
8. If successful, hold new kernel packages (replace version number):
   ```bash
   ssh dungeon-chest-004 "sudo apt-mark hold linux-image-6.8.0-XX-generic linux-headers-6.8.0-XX-generic linux-modules-6.8.0-XX-generic linux-modules-extra-6.8.0-XX-generic linux-image-generic linux-headers-generic"
   ```
9. If unsuccessful, downgrade to 6.8.0-86-generic and re-hold

**Related Documentation:**
- NVIDIA Precompiled Drivers: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/precompiled-drivers.html
- GPU Operator Platform Support: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html
- NGC Driver Catalog: https://catalog.ngc.nvidia.com/orgs/nvidia/containers/driver

**Last Updated:** 2025-11-10
