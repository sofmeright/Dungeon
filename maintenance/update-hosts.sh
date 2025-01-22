#!bin/sh
ansible-playbook --limit linux -i inventory/complete.yaml maintenance/update-hosts-linux.yaml