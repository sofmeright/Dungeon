#!/bin/bash
set -euxo pipefail

# Simple FluxCD Bootstrap Script

# Install Flux CLI if not present
if ! command -v flux &> /dev/null; then
    echo "Installing Flux CLI..."
    curl -s https://fluxcd.io/install.sh | sudo bash
fi

# Bootstrap Flux with GitLab repository
flux bootstrap git \
  --url=ssh://git@10.30.1.123:2424/precisionplanit/ant_parade-public \
  --branch=main \
  --private-key-file="${HOME}/.ssh/id_ed25519" \
  --path=fluxcd/clusters/overlays/production

echo "Flux bootstrap complete!"
echo "Check status with: flux get all"