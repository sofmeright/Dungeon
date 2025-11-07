![Banner](./docs/assets/dungeon-banner.png)

> _"When the cluster's down, and the world is on fire, at least you can still run Ansible."_ 🔥

This repository seeks to be the source of truth regarding the active state of my Kubernetes cluster "Dungeon" and my Proxmox Cluster "Ad_Arbitorium". All system state, automation routines, and backup strategies should be declared within this repository. This Dungeon must be cleared, so we can advance to the next one!

> Maintained by [SoFMeRight](https://github.com/sofmeright) for [PrPlanIT](https://prplanit.com) — Real world results for your real world expectations.

---

## See Also:
- [Ansible (Gitlab Component)](https://github.com/sofmeright/ansible-glc)
- [Ansible OCI](https://github.com/sofmeright/ansible-oci) – Docker runtime image for Ansible workflows
- [StageFreight GitLab Component](https://github.com/sofmeright/stagefreight-glc) – GitLab component that provides CI pipeline orchestration for releases
- [StageFreight OCI (Docker Image)](https://github.com/sofmeright/stagefreight-oci) – A general-purpose DevOps automation image built to accelerate CI/CD pipelines.

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
    -v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \
    -v /srv/gitops/ad-arbitorium-private:/srv/gitops/ad-arbitorium-private:ro \
    cr.pcfae.com/prplanit/ansible:2.18.6 \
  ansible-playbook --private-key /root/.ssh/id_rsa \
  -i /srv/gitops/ad-arbitorium-private/ansible/inventory \
  /srv/gitops/ad-arbitorium-private/ansible/infrastructure/qemu-guest-agent-debian.yaml
```
##### WinRM Example:

```bash
docker run --rm \
    -v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \
    -v /srv/gitops/ad-arbitorium-private:/srv/gitops/ad-arbitorium-private:ro \
    -v ./playbook.yaml:/root/playbook.yaml:ro \
    cr.pcfae.com/prplanit/ansible:2.18.6 \
  ansible-playbook \
    --private-key /root/.ssh/id_rsa \
    -i /srv/gitops/ad-arbitorium-private/ansible/inventory \
    /root/playbook.yaml \
    -e ansible_windows_password="${WINDOWS_ANSIBLE_PASSWORD}"
```

## 📅 Backup Schedule

Our peak hours are typically 6:00AM – 10:00PM PST. Backups are scheduled to minimize risk during these times.

| Day           | Time  | Task                                             |
| ------------- | ----- | ------------------------------------------------ |
| Daily         | 18:00 | Dungeon (K8s) Backup via Velero                  |
| Mon, Fri      | 22:00 | NAS & PBS → local-zfs backup                     |
| Tue, Thu, Fri | 23:00 | All other core/essential VMs → Flashy-Fuscia-SSD |

## 🖥️ Hardware Overview

### Proxmox VE Cluster

| Host           | CPU                                         | RAM                |
| -------------- | ------------------------------------------- | ------------------ |
| 🥑 Avocado     | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 256GB (8×32GB ECC) |
| 🎍 Bamboo      | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 96GB (6×16GB ECC)  |
| 🌌 Cosmos      | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 256GB (8×32GB ECC) |
| 🐉 Dragonfruit | AMD Ryzen 7 2700X (8C/16T) 3.7–4.35GHz      | 64GB (2×32GB ECC)  |
| 🍆 Eggplant    | 2× Xeon E5-2618L v4 (20C/40T) 2.20–3.20 GHz | 128GB (16×8GB ECC) |

####  Unclustered automation node

| Host               | CPU                                         | RAM                | Purpose                                                                                             |
| ------------------ | ------------------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------- |
| 🪲 leaf-cutter     | Intel i7-4720HQ (8 threads @ 3.6GHz)        | 16GB (2×8GB DDR3) | This node runs critical automation if the cluster fails. Think of it as "ant-parade's stunt double." |

I provide more in-depth Hardware information [HERE](./docs/Hardware.md) if you are interested in that.

## 🧠 Observability & Monitoring

| Technology           | Purpose Used                                                                 |
| -------------------- | ---------------------------------------------------------------------------- |
| Grafana              | Amazing dashboard for Metrics, Logs, Tracing, Security, many other usecases! |
| Loki                 | Logging, collection and aggregation                                          |
| Mimir                | Metrics                                                                      |
| Crowdsec             | Open Source Crowd Based Threat Detection and Prevention System, with pfsense & other integrations |
| Beszel               | alternative option for viewing some metrics                                  |
| Wazuh                | SIEM, I haven't had the chance to get as familiar with this one              |

Some Dashboards and UIs I frequently use to manage / observe Containerized Environments:
- Weave-Gitops
- FreeLens 
- Portainer

## 🌐 Networking

| Technology           | Purpose Used                                                         |
| -------------------- | -------------------------------------------------------------------- |
| pfSense              | 2 VMs running on Avocado & Bamboo Highly Available routing via CARP. |
| OSPFv6               | Proxmox/Ceph private/internal network                                |
| BGP                  | Kubernetes Load Balancers (Cillim peers with pfsense).               |
| kube-vip             | Kubernetes API Load balancing                                        |
| Istio                | The chosen cluster mesh.                                             |
| AdGuardHome          | DNS Server & Highly Available with 1 master and 1 replica, likely migrating to Technitium  or Gravity soon. |

##### Reverse Proxies:

- cell-membrane, phloem, and xylem handle NGINX proxy duties
> Internal domains like *.pcfae.com live inside xylem (no external exposure)
- In the process of migrating most of the nginx configs to a Istio + Gateway API solution.

## 📞 Remote Access Tools
| Technology           | Purpose Used                                                         |
| -------------------- | -------------------------------------------------------------------- |
| Moonlight/Sunshine   | Remote Desktop. Sunshine is the Server, Moonlight is the Client. Gaming friendly and they package clients for most every device. |
| Rustdesk             | Its basically self hosted AnyDesk. It works. |
| Tactical-RMM         | Full featured Remote Monitoring & Management system. |

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

## 📦 [Docker Stacks](./docker-compose/README.md)

> A list of all the docker containers that I have deployed can be reviewed via the [README.md](./docker-compose/README.md) in the docker-compose directory.

## Kubernetes Deployments

[A list of all my kubernetes deployments](./docs/Apps_&_Services-Overview.md) is not formatted neatly at this time as I am under rapid construction right now. But everything I have deployed is visible within "fluxcd" as before mentioned... Cheers!

## 🤓 Want to contribute or improve the stack?
This is a private lab, but feedback, discussion, and memes are always welcome. ✉️

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/T6T41IT163)

## ⚠️ Disclaimer

> The code, images, and infrastructure templates herein (the "Software") are provided as-is and as-absurd—without warranties, guarantees, or even friendly nudges. The authors accept no liability if this repo makes your cluster self-aware, breaks your ankle (metaphorically or otherwise), or causes irreversible YAML-induced burnout.

We take no responsibility if running this setup somehow:

- launches a container into orbit,

- bricks your homelab,

- or awakens a long-dormant AI from /dev/null.

> Use at your own risk. If it works, thank the open-source gods. If it doesn't, well... you probably learned something.