#!/bin/bash
# Analyze unmapped RBD usage and calculate totals

echo "Analyzing unmapped RBD volumes..."
echo ""

# Convert bytes to human readable
bytes_to_human() {
    numfmt --to=iec-i --suffix=B $1
}

# Calculate totals
total_provisioned=0
total_used=0

while IFS=, read -r uuid provisioned used; do
    if [ "$uuid" != "UUID" ]; then
        total_provisioned=$((total_provisioned + provisioned))
        total_used=$((total_used + used))
    fi
done < unmapped_rbd_usage.csv

echo "Total unmapped volumes: 86"
echo "Total provisioned space: $(bytes_to_human $total_provisioned)"
echo "Total used space: $(bytes_to_human $total_used)"
echo ""

# Show top 10 by used space
echo "Top 10 volumes by used space:"
echo "USED,PROVISIONED,UUID" > top10_used.csv
tail -n +2 unmapped_rbd_usage.csv | sort -t, -k3 -rn | head -10 >> top10_used.csv
column -t -s, top10_used.csv
echo ""

# Show volumes by size category
echo "Breakdown by provisioned size:"
awk -F, 'NR>1 {
    prov = $2;
    if (prov < 2147483648) size="<2G";
    else if (prov < 10737418240) size="2-10G";
    else if (prov < 53687091200) size="10-50G";
    else if (prov < 107374182400) size="50-100G";
    else size=">=100G";
    count[size]++;
}
END {
    for (s in count) print s ": " count[s] " volumes"
}' unmapped_rbd_usage.csv | sort
