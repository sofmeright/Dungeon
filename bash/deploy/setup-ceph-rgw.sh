#!/bin/bash
set -e

echo "=== Ceph RGW Setup for dungeon cluster ==="
echo ""
echo "This script installs and configures Ceph RGW on Proxmox"
echo "Run this script on a Proxmox node with Ceph access"
echo ""

# Configuration
REALM="dungeon"
ZONEGROUP="default"
ZONE="default"
RGW_HOST=$(hostname)
RGW_PORT="7480"
ENDPOINT="http://${RGW_HOST}:${RGW_PORT}"

# Pool names
METADATA_POOL="dungeon-rgw"
DATA_POOL="dungeon-rgw-data"

echo "Step 0: Install radosgw package"
if dpkg -l | grep -q radosgw; then
    echo "  radosgw package already installed"
else
    echo "  Installing radosgw package..."
    apt update
    apt install -y radosgw
    echo "  radosgw package installed"
fi
echo ""

echo "Step 1: Create realm"
if radosgw-admin realm get --rgw-realm=$REALM 2>/dev/null; then
    echo "  Realm $REALM already exists"
else
    radosgw-admin realm create --rgw-realm=$REALM --default
    echo "  Created realm: $REALM"
fi

echo ""
echo "Step 2: Create zonegroup"
if radosgw-admin zonegroup get --rgw-zonegroup=$ZONEGROUP 2>/dev/null; then
    echo "  Zonegroup $ZONEGROUP already exists"
else
    radosgw-admin zonegroup create --rgw-zonegroup=$ZONEGROUP --rgw-realm=$REALM --master --default
    echo "  Created zonegroup: $ZONEGROUP"
fi

echo ""
echo "Step 3: Create zone with custom pool configuration"
if radosgw-admin zone get --rgw-zone=$ZONE 2>/dev/null; then
    echo "  Zone $ZONE already exists, updating configuration..."
else
    radosgw-admin zone create --rgw-zonegroup=$ZONEGROUP --rgw-zone=$ZONE --master --default --endpoints=$ENDPOINT
    echo "  Created zone: $ZONE"
fi

echo ""
echo "Step 4: Configure zone to use custom pools"

# Get existing zone config and extract IDs
ZONE_ID=$(radosgw-admin zone get --rgw-zone=$ZONE | grep '"id"' | head -1 | awk -F'"' '{print $4}')
REALM_ID=$(radosgw-admin realm get --rgw-realm=$REALM | grep '"id"' | head -1 | awk -F'"' '{print $4}')

# Create zone configuration with custom pool names
cat > /tmp/rgw-zone-config.json <<EOF
{
    "id": "$ZONE_ID",
    "name": "$ZONE",
    "domain_root": "$METADATA_POOL.root",
    "control_pool": "$METADATA_POOL.control",
    "gc_pool": "$METADATA_POOL.gc",
    "lc_pool": "$METADATA_POOL.lc",
    "log_pool": "$METADATA_POOL.log",
    "intent_log_pool": "$METADATA_POOL.intent",
    "usage_log_pool": "$METADATA_POOL.usage",
    "roles_pool": "$METADATA_POOL.roles",
    "reshard_pool": "$METADATA_POOL.reshard",
    "user_keys_pool": "$METADATA_POOL.users.keys",
    "user_email_pool": "$METADATA_POOL.users.email",
    "user_swift_pool": "$METADATA_POOL.users.swift",
    "user_uid_pool": "$METADATA_POOL.users.uid",
    "otp_pool": "$METADATA_POOL.otp",
    "notif_pool": "$METADATA_POOL.notif",
    "topics_pool": "$METADATA_POOL.topics",
    "account_pool": "$METADATA_POOL.accounts",
    "group_pool": "$METADATA_POOL.groups",
    "system_key": {
        "access_key": "",
        "secret_key": ""
    },
    "placement_pools": [
        {
            "key": "default-placement",
            "val": {
                "index_pool": "$METADATA_POOL.buckets.index",
                "storage_classes": {
                    "STANDARD": {
                        "data_pool": "$DATA_POOL"
                    }
                },
                "data_extra_pool": "$METADATA_POOL.buckets.non-ec",
                "index_type": 0,
                "inline_data": true
            }
        }
    ],
    "realm_id": "$REALM_ID"
}
EOF

radosgw-admin zone set --rgw-zone=$ZONE --infile=/tmp/rgw-zone-config.json
echo "  Applied zone configuration with custom pools"

echo ""
echo "Step 5: Update zonegroup to link zone"
ZONEGROUP_ID=$(radosgw-admin zonegroup get --rgw-zonegroup=$ZONEGROUP | grep '"id"' | head -1 | awk -F'"' '{print $4}')

cat > /tmp/rgw-zonegroup-config.json <<EOF
{
    "id": "$ZONEGROUP_ID",
    "name": "$ZONEGROUP",
    "api_name": "$ZONEGROUP",
    "is_master": true,
    "endpoints": ["$ENDPOINT"],
    "hostnames": [],
    "hostnames_s3website": [],
    "master_zone": "$ZONE_ID",
    "zones": [
        {
            "id": "$ZONE_ID",
            "name": "$ZONE",
            "endpoints": ["$ENDPOINT"]
        }
    ],
    "placement_targets": [
        {
            "name": "default-placement",
            "tags": [],
            "storage_classes": ["STANDARD"]
        }
    ],
    "default_placement": "default-placement",
    "realm_id": "$REALM_ID"
}
EOF

radosgw-admin zonegroup set --rgw-zonegroup=$ZONEGROUP --infile=/tmp/rgw-zonegroup-config.json
echo "  Updated zonegroup configuration"

echo ""
echo "Step 6: Commit period"
radosgw-admin period update --commit
echo "  Period committed"

echo ""
echo "=== RGW Configuration Complete ==="
echo ""
echo "Configured pools:"
echo "  - $METADATA_POOL (metadata)"
echo "  - $DATA_POOL (object data)"
echo ""
echo "RGW Endpoint: $ENDPOINT"
echo ""
echo "Next steps:"
echo "  1. Start RGW service on this Proxmox node:"
echo "     systemctl enable ceph-radosgw@radosgw.${RGW_HOST}.service"
echo "     systemctl start ceph-radosgw@radosgw.${RGW_HOST}.service"
echo ""
echo "  2. Verify RGW is running:"
echo "     systemctl status ceph-radosgw@radosgw.${RGW_HOST}.service"
echo "     curl http://localhost:${RGW_PORT}"
echo ""
echo "  3. Create admin ops user for Rook:"
echo "     radosgw-admin user create --uid=rgw-admin-ops-user --display-name='RGW Admin Ops User' --caps='users=*;buckets=*;usage=read;metadata=read;zone=read'"
echo ""

# Actually start RGW service
echo "Starting RGW service..."
systemctl enable ceph-radosgw@radosgw.${RGW_HOST}.service
systemctl restart ceph-radosgw@radosgw.${RGW_HOST}.service
sleep 5
echo "RGW service started"
echo ""

# Actually create the admin ops user
echo "Creating admin ops user..."
if radosgw-admin user info --uid=rgw-admin-ops-user 2>/dev/null; then
    echo "Admin ops user already exists"
else
    radosgw-admin user create --uid=rgw-admin-ops-user --display-name="RGW Admin Ops User" --caps="users=*;buckets=*;usage=read;metadata=read;zone=read"
    echo "Admin ops user created"
fi

# Cleanup temp files
rm -f /tmp/rgw-zone-config.json /tmp/rgw-zonegroup-config.json
