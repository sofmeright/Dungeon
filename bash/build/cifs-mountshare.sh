#!/bin/bash

set -x

mount_list=( "/mnt/pve" "/mnt/media" "/mnt/tv" )
retry_sleep_sec=2


for mount_path in "${mount_list[@]}"; do
        until [ $(mount $mount_path) ]; do
                sleep $retry_sleep_sec
            done
    done