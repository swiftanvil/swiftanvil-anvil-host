#!/bin/bash
set -euo pipefail

REPO="swiftanvil/swiftanvil-anvil-host"
BINARY_NAME="anvil-host"
INSTALL_DIR="/usr/local/bin"

# Determine latest release version from GitHub
echo "Fetching latest ${BINARY_NAME} release..."
LATEST_URL=$(curl -sL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"browser_download_url":' \
  | grep "${BINARY_NAME}" \
  | head -1 \
  | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "${LATEST_URL}" ]; then
  echo "Error: Could not find a pre-built binary for ${BINARY_NAME}."
  echo "You can build from source instead:"
  echo "  git clone https://github.com/${REPO}.git"
  echo "  cd $(basename "${REPO}")"
  echo "  swift build -c release"
  exit 1
fi

VERSION=$(basename "$(dirname "${LATEST_URL}")")
echo "Installing ${BINARY_NAME} ${VERSION}..."

# Download to a temporary location
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

curl -sL -o "${TMP_DIR}/${BINARY_NAME}" "${LATEST_URL}"
chmod +x "${TMP_DIR}/${BINARY_NAME}"

# Install system-wide
echo "Installing binary to ${INSTALL_DIR}/${BINARY_NAME}..."
sudo mkdir -p "${INSTALL_DIR}"
sudo cp -f "${TMP_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
sudo chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

# Verify installation
if "${INSTALL_DIR}/${BINARY_NAME}" help >/dev/null 2>&1; then
  echo "✅ ${BINARY_NAME} installed successfully."
else
  echo "⚠️  Installation may have failed. Try running:"
  echo "   ${INSTALL_DIR}/${BINARY_NAME} help"
  exit 1
fi

echo ""
echo "Next steps:"
echo "  sudo ${BINARY_NAME} provision    # Full host setup"
echo "  ${BINARY_NAME} status            # Check host health"
