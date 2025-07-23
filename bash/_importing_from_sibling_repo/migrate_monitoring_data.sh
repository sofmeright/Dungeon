# This script pulls data from the source to the new monitoring stack location.
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/beszel/ /mnt/app_data/Server/_docker_stack/beszel/
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/grafana/ /mnt/app_data/Server/_docker_stack/grafana/
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/graphite-exporter/ /mnt/app_data/Server/_docker_stack/graphite-exporter/
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/loki/ /mnt/app_data/Server/_docker_stack/loki/
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/ntfy/ /mnt/app_data/Server/_docker_stack/ntfy/
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/prometheus/ /mnt/app_data/Server/_docker_stack/prometheus/
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/prometheus-eaton-ups-exporter/ /mnt/app_data/Server/_docker_stack/prometheus-eaton-ups-exporter/
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/prometheus-pve-exporter/ /mnt/app_data/Server/_docker_stack/prometheus-pve-exporter/
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/promtail/ /mnt/app_data/Server/_docker_stack/promtail/
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/uptime-kuma/ /mnt/app_data/Server/_docker_stack/uptime-kuma/
sudo rsync -avz kai@moor:/mnt/app_data/Server/_docker_stack/wazuh/ /mnt/app_data/Server/_docker_stack/wazuh/
