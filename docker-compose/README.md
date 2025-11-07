
## 🧠 Observability & Monitoring
- Grafana + Loki + Prometheus for metrics & logs
- Crowdsec for IDS/IPS and pfsense integration
- Beszel alternative option for metrics
- Wazuh
- Portainer for container management dashboards

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
> In the meantime all deployments can be reviewed within the repository in the case this list is inaccurate.