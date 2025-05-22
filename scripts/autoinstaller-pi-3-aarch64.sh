#!/bin/bash

# IotPilot Raspberry Pi 3 Model B Installer
# This script installs IotPilot directly on a Raspberry Pi 3 Model B running Debian Bookworm
# Usage:
#   sudo apt install curl
#   Basic: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-3-aarch64.sh | sudo bash
#   With Tailscale key: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-3-aarch64.sh | sudo TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash
#   With Tailscale key and custom hostname: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-3-aarch64.sh | sudo TAILSCALE_HOSTNAME="custom-name" TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash

set -e

# Source common functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/common-installer-functions.sh"

# Check if running as root
check_root

# Detect Raspberry Pi model
# Detect Raspberry Pi model
detect_raspberry_pi() {
  # Default to false
  IS_RASPBERRY=false
  IS_PI_3=false

  if [ ! -f /proc/device-tree/model ]; then
    warn "Could not detect Raspberry Pi model. Installation might not work correctly."
  else
    MODEL=$(tr -d '\0' < /proc/device-tree/model)
    info "Detected: $MODEL"
    if [[ "$MODEL" == *"Raspberry Pi"* ]]; then
      IS_RASPBERRY=true
      info "Raspberry Pi detected - will use specialized configuration"

      if [[ "$MODEL" == *"Pi 3"* ]]; then
        IS_PI_3=true
        info "Raspberry Pi 3 detected"

        # Check architecture
        ARCH=$(uname -m)
        info "Running on $ARCH architecture"

        if [[ "$ARCH" == "aarch64" ]]; then
          info "Detected 64-bit ARM architecture"
        elif [[ "$ARCH" == "armv7l" ]]; then
          info "Detected 32-bit ARM architecture"
        else
          warn "Unexpected architecture: $ARCH - will try to continue anyway"
        fi
      fi
    else
      warn "This doesn't appear to be a Raspberry Pi. Will use standard configuration."
    fi
  fi

  # Export the variables so they're available to other functions
  export IS_RASPBERRY
  export IS_PI_3
}

# Install Node.js for Raspberry Pi 3 with ARM64 (aarch64)
install_nodejs() {
  info "Installing Node.js 16.x for ARM64 architecture..."

  # Check the actual architecture of the machine
  ARCH=$(uname -m)
  info "Detected architecture: $ARCH"

  # Verify we're on ARM64
  if [[ "$ARCH" != "aarch64" ]]; then
    warn "This script is optimized for ARM64 (aarch64) architecture, but detected $ARCH"
    warn "Installation may not be optimal for this architecture"
  fi

  # Check if Node.js is already installed and working
  if command -v node &> /dev/null; then
    if node --version &> /dev/null; then
      NODE_VERSION=$(node --version)
      info "Node.js is already installed and working: $NODE_VERSION"

      # Check for npm
      if npm --version &> /dev/null; then
        NPM_VERSION=$(npm --version)
        info "npm $NPM_VERSION is also installed and working"

        # Store the path to node for later use
        NODEJS_PATH=$(which node)
        info "Node.js binary located at: $NODEJS_PATH"
        export NODEJS_PATH

        return 0
      fi
    fi
    info "Node.js is installed but may not be working correctly. Will reinstall."
  fi

  # Install Node.js using the NodeSource repository for ARM64
  info "Installing Node.js 16.x using NodeSource repository for ARM64..."

  # Add NodeSource repository with architecture detection
  curl -fsSL https://deb.nodesource.com/setup_16.x | bash - || {
    error "Failed to add NodeSource repository. Cannot continue."
    return 1
  }

  # Install Node.js from repository
  apt-get install -y nodejs || {
    error "Failed to install Node.js from repository. Cannot continue."
    return 1
  }

  # Verify installation
  NODE_VERSION=$(node --version)
  if [ $? -eq 0 ]; then
    info "Node.js $NODE_VERSION installed successfully from NodeSource repository"

    # Store the path to node for later use
    NODEJS_PATH=$(which node)
    info "Node.js binary located at: $NODEJS_PATH"
    export NODEJS_PATH

    # Check for npm
    NPM_VERSION=$(npm --version)
    if [ $? -eq 0 ]; then
      info "npm $NPM_VERSION is also installed and working"
    else
      warn "npm does not appear to be working correctly"
    fi

    # Additional setup for ARM64: Install common global packages
    info "Installing global npm packages..."
    npm install -g nodemon || warn "Failed to install nodemon globally"

    return 0
  else
    error "Node.js installation verification failed"
    return 1
  fi
}

# We'll define a Pi 3 specific function to handle the node_modules installation
setup_pi3_node_modules() {
  local repo_dir="/opt/iotpilot"

  # Check architecture for correct pre-compiled modules
  ARCH=$(uname -m)
  if [[ "$ARCH" == "aarch64" ]]; then
    info "Using pre-compiled node_modules for aarch64 architecture..."

    cd "$repo_dir"

    # Path to the precompiled node_modules
    NODE_MODULES_ARCHIVE="$repo_dir/packages/arm64v8/node_modules.tar.gz"

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
      warn "Pre-compiled node_modules not found at $NODE_MODULES_ARCHIVE. Falling back to direct installation."

      # Fall back to direct installation if pre-compiled package not found
      cd "$repo_dir/app"
      info "Installing Node.js dependencies (this may take a while)..."

      # Set larger memory limit for Node.js to avoid memory issues during installation
      export NODE_OPTIONS="--max-old-space-size=512"
      npm install --no-optional || warn "Some dependencies may not have installed correctly"
    fi
  else
    # For other architectures, do direct npm install
    cd "$repo_dir/app"
    info "Installing Node.js dependencies for $ARCH architecture (this may take a while)..."

    # Set larger memory limit for Node.js to avoid memory issues during installation
    export NODE_OPTIONS="--max-old-space-size=512"
    npm install --no-optional || warn "Some dependencies may not have installed correctly"
  fi

  # Fix permissions
  chown -R iotpilot:iotpilot "$repo_dir"
  chmod -R 755 "$repo_dir"
}

# For create_systemd_service, we need to set NODE_PATH before calling it
set_node_path() {
  # Find node executable path
  NODE_PATH=${NODEJS_PATH:-$(which node)}

  if [ -z "$NODE_PATH" ]; then
    # If we still couldn't find it, check common locations
    if [ -f "/usr/bin/node" ]; then
      NODE_PATH="/usr/bin/node"
    elif [ -f "/usr/local/bin/node" ]; then
      NODE_PATH="/usr/local/bin/node"
    else
      error "Could not find Node.js executable. Please install Node.js and try again."
      return 1
    fi
  fi

  info "Using Node.js from: $NODE_PATH"
  export NODE_PATH
}

# Main installation process
main() {
  echo
  echo -e "${GREEN}=============================================${NC}"
  echo -e "${GREEN}   IotPilot Pi 3 Installer Script            ${NC}"
  echo -e "${GREEN}=============================================${NC}"
  echo

  echo "This script will install IotPilot directly on your Raspberry Pi 3."
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
  setup_pi3_node_modules
  set_node_path
  create_systemd_service
  setup_tailscale_autofix
  show_information "Pi 3"
}

# Run the main installation function
main

exit 0
