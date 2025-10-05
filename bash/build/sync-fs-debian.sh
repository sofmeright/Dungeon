#!/bin/bash
# -----------------------------------------------------------------------------------
# --------------------- Variables you might change ? --------------------------------
# Inventory hosts:
hosts=( "Avocado" "Bamboo" "Cosmos" "Dragonfruit" "Eggplant" "Priscilla" )
# -----------------------------------------------------------------------------------
# I wouldn't change anything past this line unless you are careful and know what you are doing.
# -----------------------------------------------------------------------------------
# set -x ~ Print shell command before execute it. This feature help programmers to track their shell script.
# set -e ~ If the return code of one command is not 0 and the caller does not check it, the shell script will exit. This feature make shell script robust.
set -xe
# -----------------------------------------------------------------------------------

for host in "${hosts[@]}"; do
    ssh root@$host "mkdir /var/lib/ceph/mon/ceph-$host/store.db /var/lib/ceph/mon/ceph-$host/store.db.original"
    rsync -av $ms/store.db/ root@$host:/var/lib/ceph/mon/ceph-$host/store.db/
    done