#!/bin/bash

set -xe
# Your path. Make sure it's large enough and empty (couple of GB for a big cluster, not the sum of OSD size)
ms=/root/mon-store
rm -r $ms || true
mkdir $ms || true
# Hosts that provide OSDs - if you don't specify a host here that has OSDs, they will become "Ghost OSDs" in rebuild and data may be lost
hosts=( "Avocado" "Bamboo" "Cosmos" )

# collect the cluster map from stopped OSDs - basically, this daisy-chains the gathering. Make
# sure to start with clean folders, or the rebuild will fail when starting ceph-mon
# (update_from_paxos assertion error) (the rm -rf is no mistake here)
for host in "${hosts[@]}"; do
  rsync -avz $ms/. root@$host:$ms.remote
  rm -rf $ms
  ssh root@$host <<EOF
    set -x
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-84c6965b-59a0-4308-8ca2-7c52024239b9/osd-block-e16735de-485e-4c07-a591-ef146028a67b --path /var/lib/ceph/osd/ceph-0
    ln -snf /dev/ceph-84c6965b-59a0-4308-8ca2-7c52024239b9/osd-block-e16735de-485e-4c07-a591-ef146028a67b /var/lib/ceph/osd/ceph-0/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-d90d45fd-63e5-46cf-8462-cebf9a0a3834/osd-block-4a3f6d78-4a7e-41a2-848d-f24241b1a1d7 --path /var/lib/ceph/osd/ceph-1
    ln -snf /dev/ceph-d90d45fd-63e5-46cf-8462-cebf9a0a3834/osd-block-4a3f6d78-4a7e-41a2-848d-f24241b1a1d7 /var/lib/ceph/osd/ceph-1/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-eeae1c73-d458-4169-9a15-991b551c1729/osd-block-efbda61d-8357-4f47-a441-f2c6e9db9d58 --path /var/lib/ceph/osd/ceph-2
    ln -snf /dev/ceph-eeae1c73-d458-4169-9a15-991b551c1729/osd-block-efbda61d-8357-4f47-a441-f2c6e9db9d58 /var/lib/ceph/osd/ceph-2/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-189d4cdf-f3a1-48f4-8f6c-bda0ba4d4a20/osd-block-5a684fa0-46a9-4c56-b551-d8c75612c68e --path /var/lib/ceph/osd/ceph-3
    ln -snf /dev/ceph-189d4cdf-f3a1-48f4-8f6c-bda0ba4d4a20/osd-block-5a684fa0-46a9-4c56-b551-d8c75612c68e /var/lib/ceph/osd/ceph-3/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-dd516926-6d74-486a-aee3-6b96fe3d3abb/osd-block-8b9fe600-45d9-4a91-95a4-138bcfaef391 --path /var/lib/ceph/osd/ceph-4
    ln -snf /dev/ceph-dd516926-6d74-486a-aee3-6b96fe3d3abb/osd-block-8b9fe600-45d9-4a91-95a4-138bcfaef391 /var/lib/ceph/osd/ceph-4/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-2a9e9114-d08a-40c0-b94b-558a09164678/osd-block-f431e4ea-4be6-4086-8a1e-646c6c060d5f --path /var/lib/ceph/osd/ceph-5
    ln -snf /dev/ceph-2a9e9114-d08a-40c0-b94b-558a09164678/osd-block-f431e4ea-4be6-4086-8a1e-646c6c060d5f /var/lib/ceph/osd/ceph-5/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-533baef8-7071-481b-a217-103731bcedec/osd-block-86437e7e-5fb9-4faf-a9e5-843bced30e3f --path /var/lib/ceph/osd/ceph-6
    ln -snf /dev/ceph-533baef8-7071-481b-a217-103731bcedec/osd-block-86437e7e-5fb9-4faf-a9e5-843bced30e3f /var/lib/ceph/osd/ceph-6/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-c5cb462a-442a-446b-a382-bf919764888f/osd-block-f7d89e38-513a-45af-8e44-8234b1339f42 --path /var/lib/ceph/osd/ceph-7
    ln -snf /dev/ceph-c5cb462a-442a-446b-a382-bf919764888f/osd-block-f7d89e38-513a-45af-8e44-8234b1339f42 /var/lib/ceph/osd/ceph-7/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-c806ec72-7c30-4d5f-b3fa-4bd1b10f9828/osd-block-9ef3b1c8-8d97-45bd-a65b-b0ca7cc6b302 --path /var/lib/ceph/osd/ceph-8
    ln -snf /dev/ceph-c806ec72-7c30-4d5f-b3fa-4bd1b10f9828/osd-block-9ef3b1c8-8d97-45bd-a65b-b0ca7cc6b302 /var/lib/ceph/osd/ceph-8/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-df6f28d1-0365-4866-9d7c-3e17d3c15382/osd-block-bc661c08-9eca-4e57-9bc5-d1e38db4a9de --path /var/lib/ceph/osd/ceph-9
    ln -snf /dev/ceph-df6f28d1-0365-4866-9d7c-3e17d3c15382/osd-block-bc661c08-9eca-4e57-9bc5-d1e38db4a9de /var/lib/ceph/osd/ceph-9/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-ea38147f-f580-4ed4-9d2f-68e931d8c959/osd-block-29a23d49-fe44-4f1c-9691-6e0a7d6dd321 --path /var/lib/ceph/osd/ceph-10
    ln -snf /dev/ceph-ea38147f-f580-4ed4-9d2f-68e931d8c959/osd-block-29a23d49-fe44-4f1c-9691-6e0a7d6dd321 /var/lib/ceph/osd/ceph-10/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-d41b77d1-4a76-4a7f-8fa3-98b02c609a4f/osd-block-c6946d00-5a5d-41d1-bbf0-75d295357181 --path /var/lib/ceph/osd/ceph-11
    ln -snf /dev/ceph-d41b77d1-4a76-4a7f-8fa3-98b02c609a4f/osd-block-c6946d00-5a5d-41d1-bbf0-75d295357181 /var/lib/ceph/osd/ceph-11/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-ed395863-e489-426b-a4f4-1695e532ff34/osd-block-57b00305-46dd-495a-a072-6b5e35efb808 --path /var/lib/ceph/osd/ceph-12
    ln -snf /dev/ceph-ed395863-e489-426b-a4f4-1695e532ff34/osd-block-57b00305-46dd-495a-a072-6b5e35efb808 /var/lib/ceph/osd/ceph-12/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-9938bb59-942b-4ae0-a92c-7f653647076b/osd-block-97651fba-d54f-449e-afd8-c2d88c441e07 --path /var/lib/ceph/osd/ceph-13
    ln -snf /dev/ceph-9938bb59-942b-4ae0-a92c-7f653647076b/osd-block-97651fba-d54f-449e-afd8-c2d88c441e07 /var/lib/ceph/osd/ceph-13/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-6703ad51-75e7-4073-8d14-cae68ce91017/osd-block-8ba44ba0-b04c-47cb-892a-a31c636c417d --path /var/lib/ceph/osd/ceph-14
    ln -snf /dev/ceph-6703ad51-75e7-4073-8d14-cae68ce91017/osd-block-8ba44ba0-b04c-47cb-892a-a31c636c417d /var/lib/ceph/osd/ceph-14/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-cf0d50cb-9675-4679-8131-1ce253028d29/osd-block-f1c39fa5-78c9-4095-b6ce-46117f2c5c49 --path /var/lib/ceph/osd/ceph-15
    ln -snf /dev/ceph-cf0d50cb-9675-4679-8131-1ce253028d29/osd-block-f1c39fa5-78c9-4095-b6ce-46117f2c5c49 /var/lib/ceph/osd/ceph-15/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-b2ec198a-ee87-44e1-9305-fd89e10a1561/osd-block-c01e9cd6-0c50-4654-a011-19a6ba6401df --path /var/lib/ceph/osd/ceph-16
    ln -snf /dev/ceph-b2ec198a-ee87-44e1-9305-fd89e10a1561/osd-block-c01e9cd6-0c50-4654-a011-19a6ba6401df /var/lib/ceph/osd/ceph-16/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-45cd1d59-6e9d-4571-a7e4-3e4e544dd819/osd-block-d071cb3f-088b-4d74-8b55-8c59b2a5f2a1 --path /var/lib/ceph/osd/ceph-17
    ln -snf /dev/ceph-45cd1d59-6e9d-4571-a7e4-3e4e544dd819/osd-block-d071cb3f-088b-4d74-8b55-8c59b2a5f2a1 /var/lib/ceph/osd/ceph-17/block
    ceph-bluestore-tool --cluster=ceph prime-osd-dir --dev /dev/ceph-e19392cd-71fc-4d6e-b0a2-3303aea2254e/osd-block-bd71d83d-7953-4f8b-9ff9-32ddea809b58 --path /var/lib/ceph/osd/ceph-18
    ln -snf /dev/ceph-e19392cd-71fc-4d6e-b0a2-3303aea2254e/osd-block-bd71d83d-7953-4f8b-9ff9-32ddea809b58 /var/lib/ceph/osd/ceph-18/block
    for osd in /var/lib/ceph/osd/ceph-*; do
      # We do need the || true here to not crash when ceph tries to recover the osd-{node}-Directory present on some hosts
      ceph-objectstore-tool --type bluestore --data-path \$osd --no-mon-config --op update-mon-db --mon-store-path $ms.remote || true
    done
EOF
  rsync -avz --remove-source-files root@$host:$ms.remote/. $ms
done

# You probably need this one on proxmox
KEYRING="/etc/pve/priv/ceph.mon.keyring"

# rebuild the monitor store from the collected map, if the cluster does not
# use cephx authentication, we can skip the following steps to update the
# keyring with the caps, and there is no need to pass the "--keyring" option.
# i.e. just use "ceph-monstore-tool $ms rebuild" instead
ceph-authtool "$KEYRING" -n mon. \
  --cap mon 'allow *'
ceph-authtool "$KEYRING" -n client.admin \
  --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *'
# add one or more ceph-mgr's key to the keyring. in this case, an encoded key
# for mgr.x is added, you can find the encoded key in
# /etc/ceph/${cluster}.${mgr_name}.keyring on the machine where ceph-mgr is
# deployed
ceph-authtool "$KEYRING" --add-key 'AQCN1FZnZ2D8KhAAZLKBwWy/GTkGRxCGVVqmQg==' -n mgr.Avocado \
  --cap mon 'allow profile mgr' --cap osd 'allow *' --cap mds 'allow *'

ceph-authtool "$KEYRING" --add-key 'AQAo01ZnnAd5OhAADTRchGiGY6KfIAwhJ1f1pw==' -n mgr.Bamboo \
  --cap mon 'allow profile mgr' --cap osd 'allow *' --cap mds 'allow *'

ceph-authtool "$KEYRING" --add-key 'AQD00lZnOU86MBAANkKMkyP0vNDljou3I/mr2Q==' -n mgr.Cosmos \
  --cap mon 'allow profile mgr' --cap osd 'allow *' --cap mds 'allow *'
# If your monitors' ids are not sorted by ip address, please specify them in order.
# For example. if mon 'a' is 10.0.0.3, mon 'b' is 10.0.0.2, and mon 'c' is  10.0.0.4,
# please passing "--mon-ids b a c".
# In addition, if your monitors' ids are not single characters like 'a', 'b', 'c', please
# specify them in the command line by passing them as arguments of the "--mon-ids"
# option. if you are not sure, please check your ceph.conf to see if there is any
# sections named like '[mon.foo]'. don't pass the "--mon-ids" option, if you are

# using DNS SRV for looking up monitors.
# This will fail if the provided monitors are not in the ceph.conf or if there is a mismatch in length. SET YOUR OWN monitor IDs here
ceph-monstore-tool $ms rebuild -- --keyring "$KEYRING" --mon-ids Avocado Bamboo Cosmos


# make a backup of the corrupted store.db just in case!  repeat for
# all monitors.
# CAREFUL here: Running the script multiple times will overwrite the backup!
mv /var/lib/ceph/mon/ceph-Bamboo/store.db /var/lib/ceph/mon/ceph-Bamboo/store.db.corrupted2

# move rebuild store.db into place.  repeat for all monitors.
cp -r $ms/store.db /var/lib/ceph/mon/ceph-Bamboo/store.db
chown -R ceph:ceph /var/lib/ceph/mon/ceph-Bamboo/store.db
# Now, rsync the files to other hosts as well. Keep in mind that "pve" in "ceph-pve" is the
# hostname and this needs to be adjusted for every host. This is also a good moment pause
#and make sure that the backup exists. Personally, I prefer copying the backup to every host 
# first and then applying it manually to be absolutely sure, but this can be automated
# Also, make sure that /root/$ms is empty on the target node
for host in "${mons[@]}"; do
    rsync -avz $ms root@mon:/root/
done