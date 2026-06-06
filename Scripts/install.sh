#!/bin/bash
set -euo pipefail

echo "Anvil Host — one-time physical setup"
echo "===================================="

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Warning: This script is optimised for Apple Silicon (arm64)."
fi

# 1. Install Rosetta 2 if missing
if ! /usr/bin/pgrep -q -x oahd; then
    echo "Installing Rosetta 2..."
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
else
    echo "Rosetta 2 already installed."
fi

# 2. Build the package
echo "Building anvil-host..."
cd "$(dirname "$0")/.."
swift build -c release

# 3. Install binary to /usr/local/bin
BINARY=".build/release/anvil-host"
DEST="/usr/local/bin/anvil-host"

echo "Installing binary to ${DEST}..."
sudo mkdir -p /usr/local/bin
sudo cp -f "${BINARY}" "${DEST}"
sudo chmod +x "${DEST}"

# 4. Run provisioning
echo "Running provision..."
sudo "${DEST}" provision

echo "Setup complete. The host will auto-start on boot and keep anvil-runner alive."
