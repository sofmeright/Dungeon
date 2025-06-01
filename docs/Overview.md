# Ad Arbitorium (Datacenter): Private Repository

This repository describes the active environment of Ad Arbitorium datacenter. Ideally all necessary configuration shall be maintained within this repo unless it would be better stored in a docker volume or within local resources.

### Automations:

*ansible-semaphore* is deployed in a vm named ant-parade and we store our code in a self-hosted and public Gitlab instance. We retain scripts for repeatable tasks in Gitlab.

### Backup Schedule:
> The industry we are in is usually active around 6:00AM-10:00PM PST tops. Other times might be business critical hours, but here we are considering the peak of the day.

```mon,fri 22:00``` Proxmox backups of NAS & PBS to *local-zfs* 

```tue,thu,fri 23:00``` Proxmox backups of all other core/essential VMs to *Flashy-Fuscia-SSD*  

### Docker Containers Hosted (some may be out of use but remain in the list):

- 2fauth
- actualbudget
- adguardhome
- adguardhome-sync
- anubis
- appflowy
- bagisto
- bazarr
- bezsel
- bitwarden (config not in repo)
- bookstack
- byparr
- calibre-web
- chrony
- code-server
- cross-seed
- crowdsec
- dailyTxt
- dolibarr
- drawio
- echoip
- endlessh
- emulatorjs
- ferdium
- filebrowser
- flaresolverr (not using)
- frappe-erpnext
- frigate
- ghost
- gitea
- gitlab
- gluetun
- gluetun-qbittorrent-port-manager
- google-webfonts-helper
- guacamole (struggling with config actually)
- hashicorp-vault (deployed to use w/ K8s, yet to implement)
- homarr
- homebox
- hrconvert2
- immich
- invoice-ninja
- it-tools
- jellyfin
- jellyseer
- joplin
- kasm
- lenpaste
- librespeed-speedtest
- libretransalate
- lidarr
- linkstack
- linkwarden
- lubelogger
- mailcow (config not in repo)
- matrix-synapse
- mealie
- monica
- monitoring-servers: beszel/grafana/loki/prometheus
- monitoring-agents: beszel-agent/cadvisor/nodeexporter
- neko
- netbird
- netbird-client(s)
- netbox
- nextcloud-aio
- nginx (experiment(ing) with docker containers, but prefer a native install in VM)
- oauth2-proxy
- ollama
- openai-whisper/fasterwhisper
- openspeedtest
- open-webui
- orangehrm
- organizr
- osticket
- overseer
- paperless-ngx
- penpot
- photoprism
- pihole
- pinchflat
- plexmediaserver
- portainer
- portainer_agent
- project-send
- prowlarr
- proxmox-backup-server
- py-kms
- pyload-ng
- qbittorrent
- radarr
- reactive-resume
- readarr
- romm
- roundcube
- rustdesk-server
- sabnzbd
- searxng
- semaphore_ui
- shinobi
- shlink
- sonarr
- speedtest-tracker
- supermicro-ipmi-license-generator
- tactical-rmm
- thelounge
- tikiwiki
- trivy
- twentycrm
- unifi-network-application
- urbackup-server
- vlmcsd
- wazuh
- whisparr
- wiki-js
- xbackbone
- zitadel

### Hardware Overview:

> Ad Arbitorium Datacenter is comprised of *5 nodes clustered* with PVE, Proxmox Virualization Environment.

1. Avocado
    - CPU: (2 x Intel Xeon E5-2680 v3) | 24C/48T 2.5GHz/3.30GHz 240Watt
    - RAM: 

2. Bamboo
    - CPU: (2 x Intel Xeon E5-2680 v4) | 28C/56T 2.4GHz/3.30GHz 240Watt

3. Cosmos
    - CPU: (2 x Intel Xeon E5-2667 v3) | 16C/32T 3.2GHz/3.60GHz 270Watt

4. Dragonfruit
    - CPU: AMD Ryzen 7 2700x | 8C/16T 3.7GHz/4.35GHz 105Watt

5. Eggplant
    - CPU: (2 x Intel Xeon E5-2683 v3) | 28C/56T 2.00GHz/3.00GHz 240Watt

### Observability/Monitoring Overview:

*Grafana/Loki/Prometheus*

*Beszel*

*Portainer*

### Networking Overview:

1. *Firewalls / Routing*: 2 pfSense Firewalls are spun up on Avocado and Bamboo with HA/CARP for stable WAN.

*Modem*

*Switches*

*OSPFv6 for Proxmox and Ceph Networking*

*BGP Kubernetes Setup*

*HA Proxy K8S API Load Balancing*

2. *DNS*: AdguardHome and AdguardHome sync docker containers within 2 VMs provides highly available DNS.

3. *Reverse Proxies*: Domains like sofmeright.com are exposed through 3 public IPs which are handled by NGINX reverse proxy services running on three distinct VMs cell-membrane, phloem, and xylem; the third has no port forwarding which creates an isolated internal web domain @ pcfae.com.

### RDP / Remote Control:

*rustdesk/moonlight/sunshine/tactical-rmm*

### Workloads (main):

*PVE* - The host OS on the main 5 nodes is PVE. Within PVE we have many guest VMs. 

*Ubuntu 24.04LTS + Docker* - The majority of our workload is managed with docker containers within Ubuntu 24.04LTS VMs. One of these hosts, Dock does have discrete GPU access.

*pfSense* - I would rather see opnSense in these 2 VMs that handle our networking needs, but the ipv4/6 dual stack networking portion of this config was not working under opnSense as of a test months before this commit.

*3Cx* - VOIP phone system.

*Home-Assistant OS*

*Kubernetes* - Deployed a 5 master/worker kubeadm cluster utilizing Ubuntu 22.04LTS. Plan on removing 2 masters due to recommendations from many kubernetes users I am connected with sharing more than 3 masters at this scale is excessive.

*Monitoring/Observability/IDS/IPS* - Lighthouse, a VM dedicated to these purposes runs Beszel, Crowdsec, Grafana, Loki, Prometheus, Wazuh. Agents pull data from most hosts. The pfsense instances have crowdsec bouncers configured to block malicious traffic upon detection.

*PBS*

*Portainer Management* - Harbormaster VM serves as a jump server for the portainer instances.

*Shinobi* - Security Camera software.

*TrueNAS*

*Windows Server / Active Directory* - Deployed a 3 machine forest.

### VPN:

*Netbird*
