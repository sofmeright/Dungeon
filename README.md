[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/T6T41IT163)


# 🏰 Ad Arbitorium (Datacenter) — Private GitOps Repository

> _"When the cluster's down, and the world is on fire, at least you can still run Ansible."_ 🔥

Welcome to the heart of Ad Arbitorium; a GitOps repository describing the active configuration of our homelab/datacenter. This repo aims to be the source of truth for system state, automation routines, and backup strategies.


---

> Maintained by [SoFMeRight](https://github.com/sofmeright) for [PrPlanIT](https://prplanit.com) — Real world results for your real world expectations.

---

## See Also:
- [Ansible (Gitlab Component)](https://gitlab.prplanit.com/components/ansible)
- [Ansible OCI](https://gitlab.prplanit.com/precisionplanit/ansible-oci) – Docker runtime image for Ansible workflows
- [StageFreight GitLab Component](https://gitlab.prplanit.com/components/stagefreight) – GitLab component that provides CI pipeline orchestration for releases
- [StageFreight OCI (Docker Image)](https://gitlab.prplanit.com/precisionplanit/stagefreight-oci) – A general-purpose DevOps automation image built to accelerate CI/CD pipelines.

---

## 📂 Repository Layout

This repository contains:
> (a simple directory structure)
- 🧪 **Ansible Playbooks**: Stored in the `ansible/*/` directory
- 🐧 **Inventory Definitions**: Locate at `ansible/inventory`
- 📦 **Docker Compose Deployments** Stored in the `docker-compose` directory
- 🕸️ **NGINX Proxy Configurations** Stored in the `nginx-extras` directory
- ⚙️ **General Configuration Files** Stored in the `fs` directory
- 💫 **FluxCD Configuration** Located at the `fluxcd` directory
- 💾 **Backup Automation & Recovery Scripts**

Where possible, configuration is version-controlled. In some cases (e.g., Docker volumes or secrets), data resides in protected resources or local mounts.

---

## ⚙️ Automations & Tooling

### 🛠️ Primary Automation: Ansible

We use [Ansible](https://www.ansible.com/) with playbooks stored in this repo and executed via:

- 🔐 [Ansible Semaphore](https://ansible-semaphore.com/) — for web-based job triggering
- 🐳 GitLab CI/CD Components — for automated GitOps-style deployments
- 💡 *Ideas in progress*: OliveTin, or Cronguru for task selection.

### 🗄️ Repository Recovery

> **ant-parade & leaf-cutter** to the rescue! 🐜

If the cluster fails, we can recover from a local repo clone on `leaf-cutter`:

```bash
docker run --rm \
  -v /srv/gitops/ad-arbitorium-private:/srv/gitops/ad-arbitorium-private \
  -v ~/.ssh/id_rsa:/root/.ssh/id_rsa \
  cr.pcfae.com/prplanit/ansible:2.18.6 \
  ansible-playbook --private-key /root/.ssh/id_rsa \
  -i /srv/gitops/ad-arbitorium-private/ansible/inventory \
  /srv/gitops/ad-arbitorium-private/ansible/infrastructure/qemu-guest-agent-debian.yaml
```
##### WinRM Example:
```
docker run -v ./playbook.yaml:/root/playbook.yaml -v /srv/gitops/ad-arbitorium-private:/srv/gitops/ad-arbitorium-private -v ~/.ssh/id_rsa:/root/.ssh/id_rsa --rm cr.pcfae.com/prplanit/ansible:2.18.6 ansible-playbook --private-key /root/.ssh/id_rsa -i /srv/gitops/ad-arbitorium-private/ansible/inventory /root/playbook.yaml -e ansible_windows_password=$WINDOWS_ANSIBLE_PASSWORD
```

## 📅 Backup Schedule

Our peak hours are typically 6:00AM – 10:00PM PST. Backups are scheduled to minimize risk during these times.

| Day           | Time  | Task                                             |
| ------------- | ----- | ------------------------------------------------ |
| Mon, Fri      | 22:00 | NAS & PBS → local-zfs backup                     |
| Tue, Thu, Fri | 23:00 | All other core/essential VMs → Flashy-Fuscia-SSD |

## 🖥️ Hardware Overview 20 x Intel(R) Xeon(R) CPU E5-2618L v4 @ 2.20GHz (2 Sockets

The datacenter is powered by Proxmox VE and consists of five clustered nodes:

| Host           | CPU                                         | RAM                |
| -------------- | ------------------------------------------- | ------------------ |
| 🥑 Avocado     | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 256GB (8×32GB ECC) |
| 🎍 Bamboo      | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 96GB (6×16GB ECC)  |
| 🌌 Cosmos      | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 256GB (8×32GB ECC) |
| 🐉 Dragonfruit | AMD Ryzen 7 2700X (8C/16T) 3.7–4.35GHz      | 64GB (2×32GB ECC)  |
| 🍆 Eggplant    | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 128GB (16×8GB ECC) |

#### 🪲 leaf-cutter (Unclustered automation node)
- CPU: Intel i7-4720HQ (8 threads @ 3.6GHz)
- RAM: 16GB (2×8GB DDR3)
- This node runs critical automation if the cluster fails. Think of it as "ant-parade's stunt double."

## 🧠 Observability & Monitoring
- Grafana + Loki + Prometheus for metrics & logs
- Crowdsec for IDS/IPS and pfsense integration
- Beszel alternative option for metrics
- Wazuh
- Portainer for container management dashboards

## 🌐 Networking Overview

##### Firewall / Routing: 
- Dual HA/CARP pfSense VMs on Avocado & Bamboo

##### Networking:

- OSPFv6 for internal Proxmox/Ceph
- BGP for Kubernetes w/ metallb
- HAProxy load balancing for K8s API
- DNS: Highly available AdGuardHome DNS pair with sync

##### Reverse Proxies:

- cell-membrane, phloem, and xylem handle NGINX proxy duties
> Internal domains like *.pcfae.com live inside xylem (no external exposure)

## 📞 Remote Access Tools
- rustdesk, moonlight, sunshine, tactical-rmm

## 🧱 Core Workloads
- PVE – Bare metal Proxmox hosts
- Ubuntu 24.04 + Docker – Most VMs run containers (including GPU workloads)
- pfSense – Dual-stack IPv4/6 (future: evaluate opnSense again)
- FusionPBX – VOIP System
- Home Assistant OS
- Kubernetes – 5-node cluster, likely reducing to 3 masters soon
- PBS (Proxmox Backup Server)
- Portainer – Jump node: harbormaster
- Shinobi – CCTV & surveillance
- TrueNAS
- Windows Server – Active Directory 3-node forest

## 🔒 VPN / Remote Access

- netbird

## 📦 Docker Stacks:

<!-- START_DEPLOYMENTS_MAP -->
| Host           | Deployed Stacks         |
| -------------- | ------------------------ |
| _common | monitoring-agents<br>speed-tests |
| _templates | monitoring-agents-gpu<br>monitoring-agents-no_gpu<br>monitoring-agents-refer |
| anchorage | monitoring-agents-gpu<br>ollama<br>stable-diffusion-webui |
| ant-parade | adguardhome-sync<br>gitlab-runner<br>monitoring-agents-no_gpu<br>portainer_agent<br>semaphore_ui |
| dock | emulatorjs<br>filebrowser<br>frigate<br>immich<br>jellyfin<br>kasm<br>libretransalate<br>media-servers<br>monitoring-agents-gpu<br>netbootxyz<br>nut-upsd<br>nutify<br>ollama<br>openai-whisper<br>photoprism<br>photoprism-ceph<br>photoprism-x<br>plex-ms<br>plex-ms-old<br>plex-ms-x<br>portainer<br>portainer_agent<br>shinobi |
| gringotts | caches_y_registries<br>git-sync<br>monitoring-agents-no_gpu<br>project-send<br>proxmox_bs<br>urbackup-server |
| harbormaster | monitoring-agents-no_gpu<br>portainer |
| homing-pigeon | monitoring-agents-no_gpu |
| jabu-jabu | ark-se-TMC-active<br>ark-se-TMC-inactive<br>bagisto-demo<br>calibre-web<br>drawio<br>ghost-sfmr<br>google-webfonts-helper<br>hrconvert2<br>it-tools<br>linkstack-sfmr<br>mealie<br>minecraft-servers<br>monitoring-agents-no_gpu<br>netbird-client<br>pinchflat<br>portainer-agent<br>reactive-resume<br>searxng<br>speed-tests<br>supermicro-ipmi-license-generator<br>vlmcsd |
| leaf-cutter | monitoring-agents-gpu |
| lighthouse | ids_ips<br>monitoring-agents-no_gpu<br>monitoring-servers<br>portainer<br>portainer_agent<br>speed-tests |
| marina | 2fauth<br>actualbudget<br>dailytxt<br>ferdium<br>homebox<br>linkwarden<br>lubelogger<br>monica<br>monitoring-agents-no_gpu<br>netbird-client<br>nginx<br>paperless-ngx<br>roundcube |
| moor | _bitwarden_config_needed<br>_mailcowdockerized_config_needed<br>anubis_demo<br>appflowy_cloud<br>beszel<br>bookstack<br>code-server<br>container_registry<br>dolibarr<br>echoip<br>frappe-erpnext<br>gitea<br>gitlab<br>guacamole<br>gucamole-aio<br>hashicorp-vault<br>homarr<br>invoice-ninja<br>joplin<br>linkwarden<br>lubelogger<br>monitoring-agents-no_gpu<br>netbird<br>netbird-client<br>netbox<br>nextcloud-aio<br>oauth2-proxy<br>open-webui<br>openspeedtest<br>orangehrm<br>organizr<br>osticket<br>penpot<br>quay<br>rustdesk-server<br>shlink<br>tactical-rmm<br>tikiwiki<br>trivy<br>twentycrm<br>unifi-network-application<br>urbackup-server<br>wazuh<br>zitadel |
| pirates-wdda | downloads_y_vpn<br>kms_y_licensing<br>monitoring-agents-no_gpu<br>py-kms<br>romm<br>speed-tests<br>vlmcsd<br>whisparr |
| the-lost-woods | code-server<br>customer-demos<br>echoip<br>endlessh<br>lenpaste<br>monitoring-agents-no_gpu<br>netbird-client<br>portainer-agent<br>public-resources<br>rustdesk-server<br>shlink<br>social-applications<br>tools_y_utilities<br>vegan-resources<br>xbackbone |
| the-usual-suspect | adguardhome<br>chrony<br>monitoring-agents-no_gpu<br>pihole<br>portainer_agent |
| xylem | git-sync<br>monitoring-agents-no_gpu<br>portainer<br>portainer-agent |
<!-- END_DEPLOYMENTS_MAP -->

> A full table should be populated with deployments when the pipeline runs and it will be linked to this segment in the near, near future. 

> In the meantime all deployments can be reviewed within the repository.

## 🤓 Want to contribute or improve the stack?
This is a private lab, but feedback, discussion, and memes are always welcome. ✉️

## ⚠️ Disclaimer

> The code, images, and infrastructure templates herein (the "Software") are provided as-is and as-absurd—without warranties, guarantees, or even friendly nudges. The authors accept no liability if this repo makes your cluster self-aware, breaks your ankle (metaphorically or otherwise), or causes irreversible YAML-induced burnout.

We take no responsibility if running this setup somehow:

- launches a container into orbit,

- bricks your homelab,

- or awakens a long-dormant AI from /dev/null.

> Use at your own risk. If it works, thank the open-source gods. If it doesn't, well... you probably learned something.