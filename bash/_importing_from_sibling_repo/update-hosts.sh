#!/usr/bin/env bash
ansible-playbook -i inventory/complete.yaml maintenance/update-hosts-linux_clustered.yaml
ansible-playbook -i inventory/complete.yaml maintenance/update-hosts-linux_unclustered.yaml
