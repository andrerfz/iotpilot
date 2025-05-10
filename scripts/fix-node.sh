#!/bin/bash

# Script to fix Node.js on Raspberry Pi Zero
# This script completely removes the existing Node.js installation
# and installs a compatible version directly from binaries

set -e

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print colored messages
info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  exit 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  error "Please run as root (sudo)"
fi

# Fix hostname in /etc/hosts
fix_hostname() {
  info "Fixing hostname in /etc/hosts"

  # Get current hostname
  CURRENT_HOSTNAME=$(hostname)

  # Make sure the current hostname is in /etc/hosts
  if grep -q "127.0.1.1.*$CURRENT_HOSTNAME" /etc/hosts; then
    info "Current hostname $CURRENT_HOSTNAME is already in /etc/hosts"
  else
    info "Adding $CURRENT_HOSTNAME to /etc/hosts"
    # Clean up any existing entries
    sed -i '/127.0.1.1/d' /etc/hosts
    # Add correct entry
    echo "127.0.1.1       $CURRENT_HOSTNAME" >> /etc/hosts
  fi

  # We don't need to add 'iotpilot' to /etc/hosts since mDNS will handle that
  info "Hostname resolution fixed for $CURRENT_HOSTNAME"
}

# Remove broken Node.js installation
remove_nodejs() {
  info "Removing existing Node.js installation..."

  # Stop any running processes that might be using Node.js
  killall node 2>/dev/null || true

  # Remove Node.js packages
  dpkg --remove --force-all nodejs npm 2>/dev/null || true
  apt-get remove -y nodejs npm 2>/dev/null || true
  apt-get autoremove -y 2>/dev/null || true

  # Remove Node.js binaries
  rm -rf /usr/bin/node /usr/bin/npm /usr/bin/npx 2>/dev/null || true
  rm -rf /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx 2>/dev/null || true

  # Remove Node.js directories
  rm -rf /usr/lib/node_modules 2>/dev/null || true
  rm -rf /usr/local/lib/node_modules 2>/dev/null || true

  # Remove NodeSource repositories
  rm -f /etc/apt/sources.list.d/nodesource*.list 2>/dev/null || true

  # Update package lists
  apt-get update

  info "Existing Node.js installation removed"
}

# Install Node.js from binaries
install_nodejs() {
  info "Installing Node.js directly from binaries..."

  # Determine architecture
  if [ "$(uname -m)" = "armv6l" ]; then
    NODE_ARCH="armv6l"
  elif [ "$(uname -m)" = "armv7l" ]; then
    NODE_ARCH="armv7l"
  else
    NODE_ARCH="armv6l"  # Default to armv6l for Raspberry Pi Zero
  fi

  NODE_VERSION="v16.20.2"  # Use v16 which is known to work well on Pi Zero
  NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz"

  info "Using Node.js ${NODE_VERSION} for ${NODE_ARCH} architecture"
  info "Downloading from ${NODE_URL}"

  # Download Node.js binary
  if ! wget -O /tmp/node.tar.gz "${NODE_URL}"; then
    error "Failed to download Node.js"
  fi

  # Create directory for extraction
  mkdir -p /usr/local/nodejs

  # Extract to directory
  if ! tar -xzf /tmp/node.tar.gz -C /usr/local/nodejs --strip-components=1; then
    error "Failed to extract Node.js"
  fi

  # Create symlinks
  ln -sf /usr/local/nodejs/bin/node /usr/local/bin/node
  ln -sf /usr/local/nodejs/bin/npm /usr/local/bin/npm
  ln -sf /usr/local/nodejs/bin/npx /usr/local/bin/npx

  # Verify installation
  if [ -x /usr/local/bin/node ]; then
    NODE_VERSION=$(/usr/local/bin/node --version 2>/dev/null || echo "failed")
    if [ "${NODE_VERSION}" = "failed" ]; then
      error "Node.js installation verification failed"
    else
      info "Node.js ${NODE_VERSION} installed successfully"
    fi
  else
    error "Node.js binary not found after installation"
  fi

  # Clean up
  rm -f /tmp/node.tar.gz
}

# Main function
main() {
  echo
  echo -e "${GREEN}=============================================${NC}"
  echo -e "${GREEN}  Node.js Fix for Raspberry Pi Zero          ${NC}"
  echo -e "${GREEN}=============================================${NC}"
  echo

  fix_hostname
  remove_nodejs
  install_nodejs

  echo
  echo -e "${GREEN}Node.js has been fixed successfully!${NC}"
  echo "You can verify by running:"
  echo "  node --version"
  echo "  npm --version"
  echo
  echo "Now you can run the IotPilot installer script again."
  echo
}

main