- Repository Information:
  - Git repository: ssh://git@10.30.1.123:2424/precisionplanit/dungeon
  - Repository name: dungeon (formerly ant_parade-public)
  - **Git Commits**: Only sign commits as sofmeright@gmail.com / SoFMeRight. No anthropic attribution comments in commits.

- CRITICAL RULES:
  - Prefer using flux to reconcile resources from source. We are GitOps native, we use kubectl commands to adjust state only when it is otherwise impossible!!!!!
  - When working with files in source control, make clean moves that dont create a headache of files!!!!
  - STAY ON TASK when following directions. NO BAND AID, NO FUCKING WORK AROUNDS. IF YOU THINK WE NEED TO GIVE UP or regroup and re-evaluate. ASK. DONT MAKE THE CALL ON YOUR OWN to find alternative solutions or FIND A SHORTCUT. I CAN FIND MY OWN WAYS TO BASTARDIZE THINGS I DONT NEED YOUR FUCKING HELP. I want things done exactly how I ask. If I am to be offered an alternative conversation should stop till I tell you if I agree/disagree with the alternative proposed.

- FluxCD Infrastructure Structure:
  - `fluxcd/infrastructure/controllers/base` should contain TEMPLATED infrastructure resources WITHOUT any environment-specific values including: no hardcoded namespaces, image tags, replicas, storage classes, LoadBalancer IPs, cluster-specific annotations (lbipam.cilium.io/*), domain names, URLs, etc.
  - `fluxcd/infrastructure/controllers/overlays/production` should contain ALL environment-specific infrastructure configurations and patches for the production cluster: LoadBalancer IPs, cluster-specific annotations, domain names, storage classes, etc.
  - **NAMESPACE MANAGEMENT STANDARD**: All infrastructure overlays MUST use kustomization-level `namespace:` field (standard kustomize pattern):
    - Base resources: NO namespace metadata anywhere
    - Overlay kustomization.yaml: `namespace: <target-namespace>` field at kustomization level
    - Kustomize automatically adds namespace to all resources
    - Critical for infrastructure: Avoids conflicts between FluxCD namespace (flux-system) and target deployment namespace (kube-system, etc.)
  - `fluxcd/infrastructure/configs` should only provide secrets and configuration values
  - `fluxcd/infrastructure/namespaces` manages all Kubernetes namespaces - ALL namespaces MUST be deployed via this path only
    - Namespaces (Ocarina of Time theme):
      - tingle-tuner: Tools and utilities (quirky helper character)
      - zeldas-lullaby: Administrative services (vault, weave, zitadel)
      - compass: DNS & NTP services (navigation/direction)
      - gossip-stone: Monitoring services (tells you secrets/info)
      - lost-woods: Discovery & Dashboards (exploration/finding things)
      - temple-of-time: Archival/Content Management & Media Servers (linkwarden, calibre-web, mealie, plex)
      - fairy-bottle: Backup services (velero, urbackup - restores/saves state)
      - gorons-bracelet: Storage services (minio, longhorn, rook-ceph - provides strength/lifting power)
      - arylls-lookout: Gateway for internal-only services (xylem replacement)
      - kokiri-forest: Gateway for personal/public services (phloem replacement)
      - hyrule-castle: Gateway for business/work services (cell-membrane replacement)
      - shooting-gallery: Game servers (minecraft, etc - aiming for fun)
      - lens-of-truth: IDS/IPS/SIEM security monitoring (reveals hidden threats)
  - Base should NEVER contain deployment-ready configs - only generic templates that overlays patch with real values. Base should document application defaults from upstream/vendor documentation, not production-specific configurations.
  - Always use overlays/production for actual deployment to the production cluster, never deploy from base

- Secret Management Strategy:
  - Critical infrastructure apps (vault, zitadel, etc.) use SOPS for secret management so they can run with local auth without dependencies during cluster issues
  - **CRITICAL: Never edit .enc.yaml files directly!** These are SOPS-encrypted files. Direct editing corrupts them and destroys secrets permanently. Always use `sops` command to decrypt, edit plaintext, then re-encrypt.
  - Most other applications use Vault External Secrets Operator to manage secrets from Vault at http://172.22.30.102:8200/ui/vault/secrets/operationtimecapsule/kv/list
  - Vault secret path structure in operationtimecapsule namespace:
    - `apps/<app-name>` - bundled comprehensive secrets specific to that application (e.g., apps/linkwarden)
    - `smtp/<service-name>` - SMTP-related secrets that may be shared between applications (e.g., smtp/ofcourseimvegan)
    - `smb/<share-name>` - SMB/storage secrets that may be shared between applications (e.g., smb/media-books-rw)
    - Shared paths (smtp/, smb/) are for secrets used by multiple applications, app-specific paths (apps/) are for single application use
- Container Image Standards:
  - **ALWAYS use fully qualified image names** with registry prefix (e.g., `docker.io/binwiederhier/ntfy:v2.11.0` NOT `binwiederhier/ntfy:v2.11.0`)
  - Common registries: `docker.io/` (Docker Hub), `ghcr.io/` (GitHub), `quay.io/` (Quay), `gcr.io/` (Google)
  - Prevents ImageInspectError and image pull issues in air-gapped or registry-configured clusters
  - **Container Registry Credentials**: Managed as shared resources in `infrastructure/configs/overlays/production/registries/`
    - Base template: `infrastructure/configs/base/registries/docker.io-example/`
    - Production overlays: `infrastructure/configs/overlays/production/registries/<registry>-<account>/`
    - Apps reference the pull secret by name (e.g., `cr-pcfae-admin-pull-secret`) in their deployment `imagePullSecrets`
    - Credentials stored in Vault at `registries/<registry-url>` with keys: `username`, `password`

- FluxCD App Structure:
  - `fluxcd/apps/base/<app>/` contains TEMPLATED Kubernetes resources WITHOUT any environment-specific values including: no hardcoded namespaces, image tags, replicas, storage classes, LoadBalancer IPs, cluster-specific annotations (lbipam.cilium.io/*), domain names, URLs, etc. These are reusable templates across environments.
  - `fluxcd/apps/overlays/production/<app>/` references the base (`../../../base/<app>`) and contains ALL environment-specific configurations via patches: namespace, image tags, replica counts, storage classes, LoadBalancer configurations, ingress configs, domain names, URLs, cluster-specific annotations, etc. for the production cluster.
  - **NAMESPACE MANAGEMENT STANDARD**: All overlays MUST use kustomization-level `namespace:` field (standard kustomize pattern):
    - Base resources: NO namespace metadata anywhere
    - Overlay kustomization.yaml: `namespace: <target-namespace>` field at kustomization level
    - Kustomize automatically adds namespace to all resources
    - **CRITICAL**: Use `patches:` field ONLY - `patchesStrategicMerge` is deprecated by FluxCD
    - Benefits: Standard kustomize behavior, clean and simple, no complex patches needed
  - Base should NEVER contain deployment-ready configs - only generic templates that overlays patch with real values. Base should document application defaults from upstream/vendor documentation, not production-specific configurations. If you see cluster-specific IPs, domains, or annotations in base, they must be moved to overlay patches.
  - Other environments (staging, dev) can inherit the same base with different overlays.
  - Never deploy directly from base - always use overlays for actual deployments.
- Cluster initialization is handled by bash\_importing_from_sibling_repo\bootstrap-k8s-install-dependencies.sh bootstrap-k8s-initialize-control-plane.sh and a reset script. No other manipulation should be needed for initial cluster setup.

- Helm Release Naming Standard:
  - HelmRelease metadata name should be the application name ONLY, without namespace prefix (e.g., `name: external-secrets` NOT `name: zeldas-lullaby-external-secrets`)
  - Always set `spec.releaseName` to match the application name for consistency
  - Always set `fullnameOverride` in Helm values to the application name to prevent namespace-prefixed pod names
  - Pod names should follow pattern: `<app-name>-<component>-<hash/index>` NOT `<namespace>-<app-name>-<component>-<hash/index>`
  - Examples:
    - HelmRelease name: `external-secrets`, releaseName: `external-secrets`, fullnameOverride: `external-secrets`
    - Results in pods: `external-secrets-xxxxx`, `external-secrets-webhook-xxxxx`, `external-secrets-cert-controller-xxxxx`
    - NOT: `zeldas-lullaby-external-secrets-xxxxx`
  - Benefits: Cleaner pod names, easier identification, consistent with custom StatefulSet naming

- Stateful sets should be used for PVCs that are for stateful applications! Deployments should only be used when the applications state doesnt need to be kept!

- PersistentVolume Naming Standard:
  - **NO hostPath VOLUMES**: This is a cluster - hostPath only works on a single node. Use ConfigMaps, Secrets, or PVCs instead.
  - **StatefulSet volumeClaimTemplates Behavior**: StatefulSets automatically append the StatefulSet name before the ordinal when creating PVCs from volumeClaimTemplates
    - Template naming pattern: `<namespace>-<app>-<purpose>`
    - StatefulSet name: `<app>`
    - Resulting PVC name: `<namespace>-<app>-<purpose>-<app>-<ordinal>`
    - **NOTE**: This creates intentional redundancy where the app name appears twice - this is how Kubernetes StatefulSets work and cannot be avoided without non-standard naming
  - Components:
    - `<namespace>`: The Kubernetes namespace (e.g., temple-of-time, lost-woods, gossip-stone)
    - `<app>`: The application name (e.g., jellyfin, homarr, netalertx, beszel)
    - `<purpose>`: Descriptive purpose/type identifying what the volume stores
      - For databases: Use specific DB type (postgres, mysql, sqlite, redis) NOT generic "database" or "data"
      - For storage: Use descriptive purpose (config, images, media, transcode, cache, storage, data)
    - `<ordinal>`: StatefulSet replica index (0, 1, 2, etc.)
  - **Actual PVC naming examples** (as created by StatefulSets):
    - `temple-of-time-jellyfin-config-jellyfin-0` - Jellyfin configuration (template: temple-of-time-jellyfin-config)
    - `temple-of-time-jellyfin-cache-jellyfin-0` - Jellyfin cache (template: temple-of-time-jellyfin-cache)
    - `lost-woods-homarr-sqlite-homarr-0` - Homarr SQLite database (template: lost-woods-homarr-sqlite)
    - `lost-woods-homarr-images-homarr-0` - Homarr image storage (template: lost-woods-homarr-images)
    - `gossip-stone-netalertx-config-netalertx-0` - NetAlertX configuration (template: gossip-stone-netalertx-config)
    - `gossip-stone-beszel-data-beszel-0` - Beszel data (template: gossip-stone-beszel-data)

- Ceph Storage Configuration:
  - External Ceph cluster managed via Proxmox
  - Cluster FSID: `0985467c-d8f3-4483-b27f-f0a512397ec2`
  - MON hosts: `fc00:f1:ada:104e:1ace::1-5` (IPv6)
  - **Ceph Pool Structure**:
    - `dungeon` - Primary pool for RBD (block storage for PVCs) and general Ceph usage
    - `dungeon-rgw` - RGW metadata pool (realm/zone/control/meta/log/index)
    - `dungeon-rgw-data` - RGW object data pool (actual S3 bucket objects)
  - **Ceph Users**:
    - `client.dungeon-provisioner` - RBD volume provisioner (caps: mon 'allow r, allow command "osd blacklist"', osd 'allow rwx pool=kubernetes', mgr 'allow rw')
    - `client.dungeon` - RBD volume mounter (caps: mon 'allow r', osd 'allow class-read object_prefix rbd_children, allow rwx pool=kubernetes')
    - `client.dungeon-rgw` - RADOS Gateway user (caps: mon 'allow rw', osd 'allow rwx', mgr 'allow rw')
  - **RGW (S3) Configuration**:
    - Deployed in `gorons-bracelet` namespace as StatefulSet
    - LoadBalancer IP: 172.22.30.101 (shared with storage services)
    - Endpoint: `http://ceph-rgw.gorons-bracelet.svc.cluster.local` (internal) or `http://172.22.30.101` (external)
    - Uses Ceph RBD for local cache/WAL (ReadWriteOnce PVCs)
    - Object data stored in `dungeon-rgw-data` pool via RADOS
  - **Setting up RGW pools on Proxmox Ceph cluster**:
    ```bash
    # Enable RGW on main dungeon pool (allows sharing with RBD)
    ceph osd pool application enable dungeon rgw --yes-i-really-mean-it

    # Create dedicated RGW pools with sensible naming
    ceph osd pool create dungeon-rgw 8 8           # Metadata pool
    ceph osd pool create dungeon-rgw-data 32 32    # Object data pool

    # Enable RGW application on pools
    ceph osd pool application enable dungeon-rgw rgw
    ceph osd pool application enable dungeon-rgw-data rgw
    ```

- Cluster Networking:
  - **NO MANUAL ROUTES EVER**: Cilium handles all routing via native eBPF with DSR, masquerading, BGP, LoadBalancer IPAM, and Gateway API (HTTPRoute). Never create manual ip route commands or static routes.
  - Pfsense router IPs are 172.22.144.21 & 172.22.144.23; the carp vip is 172.22.144.22. They provide BGP by peering with 172.22.144.150-154 172.22.144.170-74 and advertising routes for 172.22.30.0/24.
  - **Dual-Stack Configuration**:
    - Cluster Pod CIDR IPv4: 192.168.144.0/20
    - Cluster Pod CIDR IPv6: fc00:f1:0ca4:15a0::/56
    - Service CIDR IPv4: 10.144.0.0/12
    - Service CIDR IPv6: fc00:f1:5e1d:a007::/112
    - DNS ClusterIP: 10.144.0.10
  - **Node Network (Dual-Stack)**:
    - dungeon-chest-001  172.22.144.170  /  fc00:f1:ada:1043:1ac3::170
    - dungeon-chest-002  172.22.144.171  /  fc00:f1:ada:1043:1ac3::171
    - dungeon-chest-003  172.22.144.172  /  fc00:f1:ada:1043:1ac3::172
    - dungeon-chest-004  172.22.144.173  /  fc00:f1:ada:1043:1ac3::173
    - dungeon-chest-005  172.22.144.174  /  fc00:f1:ada:1043:1ac3::174
    - dungeon-map-001    172.22.144.150  /  fc00:f1:ada:1043:1ac3::150
    - dungeon-map-002    172.22.144.151  /  fc00:f1:ada:1043:1ac3::151
    - dungeon-map-003    172.22.144.152  /  fc00:f1:ada:1043:1ac3::152
    - dungeon-map-004    172.22.144.153  /  fc00:f1:ada:1043:1ac3::153
    - dungeon-map-005    172.22.144.154  /  fc00:f1:ada:1043:1ac3::154
    - Control Plane VIP  172.22.144.105  /  fc00:f1:ada:1043:1ac3::105
  - BGP LOAD BALANCERS:
    - General CIDR: 172.22.30.0/24.
    - Shared IPs (Ocarina of Time naming theme):
      - Administrative (e.g. vault,weave,zitadel): 172.22.30.86 (sharing-key: zeldas-lullaby)
      - General MediaServers: 172.22.30.123 (sharing-key: song-of-storms)
      - DNS & NTP, similar publicly needed core services: 172.22.30.122 (sharing-key: compass)
      - Monitoring: 172.22.30.137 (sharing-key: gossip-stone)
      - Alerting: 172.22.30.138 (sharing-key: navi)
      - Discovery & Dashboards: 172.22.30.223 (sharing-key: lost-woods)
      - Tools w/o userdata (it-tools, podinfo, searxng): 172.22.30.107 (sharing-key: tingle-tuner)
      - Archival/Content Management (linkwarden, calibre-web, mealie): 172.22.30.222 (sharing-key: song-of-time)
      - Backup services (velero, urbackup): 172.22.30.119 (sharing-key: fairy-bottle)
      - Storage services (minio, longhorn, rook-ceph): 172.22.30.101 (sharing-key: gorons-bracelet)
      - Game servers (minecraft, etc): 172.22.30.231 (sharing-key: shooting-gallery)
      - VPN-routed *arr apps (qbittorrent, prowlarr, radarr, sonarr) in swift-sail namespace: 172.22.30.33 (sharing-key: great-sea)
      - SIEM/IDS/IPS managers (wazuh-manager, crowdsec-lapi): 172.22.30.119 (sharing-key: lens-of-truth-managers)
      - SIEM/IDS/IPS dashboards (wazuh-dashboard, crowdsec-dashboard): 172.22.30.118 (sharing-key: lens-of-truth-dashboards)

- Traefik & Gateway API Routing Strategy:
  - **IP-based Domain Isolation**: Use separate Gateway resources with unique LoadBalancer IPs to enable firewall-based internet exposure control (pfSense NAT rules per IP)
  - **Gateway Architecture**:
    - **xylem-gateway** (172.22.30.69, sharing-key: arylls-lookout): Internal-only services (*.pcfae.com) - NO pfSense port forward = internal only, can be enabled on-demand
    - **phloem-gateway** (172.22.30.70, sharing-key: kokiri-forest): Personal/public services (*.sofmeright.com, *.arbitorium.com, *.yesimvegan.com) - pfSense forwards port 443
    - **cell-membrane-gateway** (172.22.30.71, sharing-key: hyrule-castle): Business/work services (*.precisionplanit.com, *.prplanit.com, *.optcp.com, *.ipleek.com, *.uni2.cc) - pfSense forwards port 443
  - Each Gateway has its own:
    - Unique LoadBalancer IP via `lbipam.cilium.io/ips` annotation
    - Dedicated TLS certificate (cert-manager + Let's Encrypt)
    - Wildcard hostname listener for its domain(s)
  - HTTPRoutes reference the appropriate Gateway via `parentRefs` and hostname matching
  - Firewall (pfSense) controls public/private exposure via port forward rules per Gateway IP
  - Benefits: Same nginx-extras isolation model, firewall-controlled exposure, k8s-native routing