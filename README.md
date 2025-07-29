# 🏰 Ad Arbitorium Datacenter — Private GitOps Repository

> _"When the cluster's down, and the world is on fire, at least you can still run Ansible."_ 🔥

Welcome to the heart of Ad Arbitorium; a GitOps repository describing the active configuration of our homelab/datacenter. This repo aims to be the source of truth for system state, automation routines, and backup strategies.


---

> Maintained by [SoFMeRight](https://github.com/sofmeright) for [PrPlanIT](https://prplanit.com) — Real world results for your real world expectations.

---

## 📂 Repository Layout

This repository contains:

- 🧪 **Ansible Playbooks**: Stored in the `ansible/*/` directory
- 🐧 **Inventory Definitions**: Locate at `ansible/inventory`
- 📦 **Docker Compose Deployments** Stored in the `docker-compose` directory
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
## 📅 Backup Schedule

Our peak hours are typically 6:00AM – 10:00PM PST. Backups are scheduled to minimize risk during these times.

| Day           | Time  | Task                                             |
| ------------- | ----- | ------------------------------------------------ |
| Mon, Fri      | 22:00 | NAS & PBS → local-zfs backup                     |
| Tue, Thu, Fri | 23:00 | All other core/essential VMs → Flashy-Fuscia-SSD |

## 🖥️ Hardware Overview

The datacenter is powered by Proxmox VE and consists of five clustered nodes:

| Host           | CPU                                     | RAM                |
| -------------- | --------------------------------------- | ------------------ |
| 🥑 Avocado     | 2× Xeon E5-2680 v3 (24C/48T) 2.5–3.3GHz | 256GB (8×32GB ECC) |
| 🎍 Bamboo      | 2× Xeon E5-2680 v4 (28C/56T) 2.4–3.3GHz | 96GB (6×16GB ECC)  |
| 🌌 Cosmos      | 2× Xeon E5-2667 v3 (16C/32T) 3.2–3.6GHz | 256GB (8×32GB ECC) |
| 🐉 Dragonfruit | AMD Ryzen 7 2700X (8C/16T) 3.7–4.35GHz  | 64GB (2×32GB ECC)  |
| 🍆 Eggplant    | 2× Xeon E5-2683 v3 (28C/56T) 2.0–3.0GHz | 128GB (16×8GB ECC) |

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

## 🤓 Want to contribute or improve the stack?
This is a private lab, but feedback, discussion, and memes are always welcome. ✉️

## ⚠️ Disclaimer

> The code, images, and infrastructure templates herein (the "Software") are provided as-is and as-absurd—without warranties, guarantees, or even friendly nudges. The authors accept no liability if this repo makes your cluster self-aware, breaks your ankle (metaphorically or otherwise), or causes irreversible YAML-induced burnout.

We take no responsibility if running this setup somehow:

- launches a container into orbit,

- bricks your homelab,

- or awakens a long-dormant AI from /dev/null.

> Use at your own risk. If it works, thank the open-source gods. If it doesn't, well... you probably learned something.