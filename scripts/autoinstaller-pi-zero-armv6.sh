#!/bin/bash

# IotPilot Raspberry Pi Zero W Rev 1.1 Installer
# This script installs IotPilot directly on a Raspberry Pi Zero W Rev 1.1 running Debian Bookworm
# Usage:
#   sudo apt install curl
#   Basic: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero-armv6.sh | sudo bash
#   With Tailscale key: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero-armv6.sh | sudo TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash
#   With Tailscale key and custom hostname: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero-armv6.sh | sudo TAILSCALE_HOSTNAME="custom-name" TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash

set -e

# Source common functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/common-installer-functions.sh"

# Check if running as root
check_root

# Detect Raspberry Pi model
detect_raspberry_pi() {
  # Default to false
  IS_RASPBERRY=false

  if [ ! -f /proc/device-tree/model ]; then
    warn "Could not detect Raspberry Pi model. Installation might not work correctly."
  else
    MODEL=$(tr -d '\0' < /proc/device-tree/model)
    info "Detected: $MODEL"
    if [[ "$MODEL" == *"Raspberry Pi"* ]]; then
      IS_RASPBERRY=true
      info "Raspberry Pi detected - will use specialized configuration"
    else
      warn "This doesn't appear to be a Raspberry Pi. Will use standard configuration."
    fi
  fi

  # Detect specifically if this is a Pi Zero
  IS_PI_ZERO=false
  if [[ "$MODEL" == *"Zero"* ]]; then
    IS_PI_ZERO=true
    info "Raspberry Pi Zero detected - will use specialized ARMv6 configuration"
  fi

  # Export the variables so they're available to other functions
  export IS_RASPBERRY
  export IS_PI_ZERO
}

# Install Node.js appropriate for the Pi Zero (ARMv6)
install_nodejs() {
  info "Installing Node.js compatible with Raspberry Pi Zero..."

  # Check if Node.js is already installed and compatible
  if command -v node &> /dev/null; then
    # Test if node works (won't work if architecture mismatch)
    if node --version &> /dev/null; then
      NODE_VERSION=$(node --version)
      info "Node.js is already installed and working: $NODE_VERSION"
      return 0
    else
      info "Node.js is installed but not working correctly. Will reinstall."
    fi
  fi

  # Remove any existing Node.js installations
  info "Removing any existing Node.js installations..."

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

  # Create temp directory
  TEMP_DIR=$(mktemp -d)
  cd "$TEMP_DIR" || return 1

  # For Pi Zero, use Node.js v16 which is more stable for ARMv6
  if [ "$IS_PI_ZERO" = true ]; then
    NODE_VERSION="16.20.2"
    info "Installing Node.js v${NODE_VERSION} for ARMv6..."

    # Download Node.js for ARMv6 (unofficial builds for Pi Zero)
    wget -q "https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-armv6l.tar.xz" -O node.tar.xz || error "Failed to download Node.js binary"

    # Extract the archive
    tar -xf node.tar.xz || error "Failed to extract Node.js archive"

    # Move to /usr/local
    mv "node-v${NODE_VERSION}-linux-armv6l" /usr/local/node
  else
    echo cat /proc/cpuinfo | grep "Model"
    info "This script doesn't support this CPU"
    return 0
  fi

  # Create symlinks
  ln -sf /usr/local/node/bin/node /usr/local/bin/node
  ln -sf /usr/local/node/bin/npm /usr/local/bin/npm
  ln -sf /usr/local/node/bin/npx /usr/local/bin/npx

  # Clean up
  cd / || return 1
  rm -rf "$TEMP_DIR"

  # Verify installation
  if ! /usr/local/bin/node --version; then
    error "Node.js installation failed"
  fi

  # Install nodemon globally
  /usr/local/bin/npm install -g nodemon || warn "Failed to install nodemon globally"

  info "Node.js v${NODE_VERSION} installed successfully"
}

# We'll define a Pi Zero specific function to handle the node_modules installation
setup_pi_zero_node_modules() {
  local repo_dir="/opt/iotpilot"

  # Use pre-compiled node_modules for Pi Zero (ARMv6)
  if [ "$IS_PI_ZERO" = true ]; then
    info "Using pre-compiled node_modules for Raspberry Pi Zero..."

    cd "$repo_dir" || return 1

    # Path to the precompiled node_modules
    NODE_MODULES_ARCHIVE="$repo_dir/packages/armv6/node_modules.tar.gz"

    if [ -f "$NODE_MODULES_ARCHIVE" ]; then
      info "Found pre-compiled node modules package at $NODE_MODULES_ARCHIVE"

      # Backup any existing node_modules
      if [ -d "$repo_dir/app/node_modules" ]; then
        info "Backing up existing node_modules..."
        mv "$repo_dir/app/node_modules" "$repo_dir/app/node_modules.backup"
      fi

      # Extract the pre-compiled node_modules
      info "Extracting pre-compiled node_modules..."
      tar -xzf "$NODE_MODULES_ARCHIVE" -C "$repo_dir/app/"

      info "Successfully installed pre-compiled node_modules"
    else
      error "Pre-compiled node_modules not found at $NODE_MODULES_ARCHIVE. This is required for Pi Zero installation."
      echo
      echo "Please make sure the repository includes the pre-built node_modules for ARMv6."
      echo "Check if the file exists at: $NODE_MODULES_ARCHIVE"
      echo
      echo "You can create this file using the build-for-pi-zero.sh script on a more powerful system,"
      echo "then commit it to your repository before running this installer."
      echo
      exit 1
    fi
  else
    # Regular dependency installation for non-Pi Zero devices
    cd "$repo_dir/app" || return 1
    info "Installing Node.js dependencies (this may take a while)..."

    # Use the installed npm from our binary installation
    NPM_BIN="/usr/local/bin/npm"

    # Tell npm to ignore engine checks for Node.js version compatibility
    info "Configuring npm to ignore engine compatibility checks..."
    $NPM_BIN config set engine-strict false

    # Try up to 3 times to install dependencies
    for i in {1..3}; do
      info "Dependency installation attempt $i..."
      "$NPM_BIN" install --unsafe-perm --ignore-scripts || {
        warn "Attempt $i failed, waiting 10 seconds before retrying..."
        if [ $i -lt 3 ]; then
          sleep 10
        else
          warn "Failed to install Node.js dependencies after 3 attempts, but continuing anyway"
        fi
        continue
      }
      info "Dependencies installed successfully!"
      break
    done
  fi

  # Fix permissions
  chown -R iotpilot:iotpilot "$repo_dir"
  chmod -R 755 "$repo_dir"
}

# For create_systemd_service, we need to set NODE_PATH before calling it
set_node_path() {
  # For Pi Zero, we know the Node.js path is at /usr/local/bin/node
  NODE_PATH="/usr/local/bin/node"
  info "Using Node.js from: $NODE_PATH"
  export NODE_PATH
}

# Main installation process
main() {
  echo
  echo -e "${GREEN}=============================================${NC}"
  echo -e "${GREEN}   IotPilot Pi Zero Installer Script         ${NC}"
  echo -e "${GREEN}=============================================${NC}"
  echo

  echo "This script will install IotPilot directly on your Raspberry Pi Zero."
  echo "The installation process might take several minutes."
  echo

  # Run installation steps
  detect_raspberry_pi
  install_system_dependencies
  fix_hostname_resolution
  install_nodejs
  setup_mdns
  install_tailscale
  install_traefik
  setup_pi_zero_node_modules
  set_node_path
  create_systemd_service
  setup_tailscale_autofix
  show_information "Pi Zero"
}

# Run the main installation function
main

exit 0
