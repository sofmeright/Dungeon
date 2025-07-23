#!/bin/bash

# Define the files to find and delete
files=(
  ".smbcreds"
  "system.yaml"
  "ceph.conf"
  "*.env"  # Glob pattern for any file ending in .env
)

# Use find to locate the files and then xargs to delete them
find "$PWD" -name -("[${files[@]}]") -print0 | xargs -0 rm -f

echo "Files matching the criteria have been deleted (or would have been).  CHECK CAREFULLY!"
read -p "Press Enter to exit..."