#!/bin/bash

# IotPilot Raspberry Pi 3 Model B Installer
# This script installs IotPilot directly on a Raspberry Pi 3 Model B running Debian Bookworm
# Usage:
#   sudo apt install curl
#   Basic: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-3-aarch64.sh | sudo bash
#   With Tailscale key: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-3-aarch64.sh | sudo TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash

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

# Install system dependencies
install_system_dependencies() {
  info "Updating package lists..."
  apt-get update -y || error "Failed to update package lists"

  info "Installing required system packages..."
  apt-get install -y \
    git \
    make \
    curl \
    avahi-daemon \
    jq \
    openssl \
    libssl-dev \
    libtool \
    build-essential \
    libsqlite3-dev \
    xz-utils \
    wget \
    ca-certificates \
    || error "Failed to install required system packages"
}

# Fix hostname resolution issues
fix_hostname_resolution() {
  info "Fixing hostname resolution..."

  # Get current hostname
  CURRENT_HOSTNAME=$(hostname)
  info "Current hostname is: $CURRENT_HOSTNAME"

  # Create a clean /etc/hosts file
  cat > /etc/hosts << EOL
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters

127.0.1.1 ${CURRENT_HOSTNAME}
EOL

  info "Updated hosts file with correct hostname entry"

  # Configure hostname to be 'iotpilot' if it's not already
  if [ "$CURRENT_HOSTNAME" != "iotpilot" ]; then
    info "Setting hostname to 'iotpilot'..."
    hostnamectl set-hostname iotpilot

    # Update /etc/hosts again with new hostname
    cat > /etc/hosts << EOL
127.0.0.1 localhost
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters

127.0.1.1 iotpilot
EOL

    info "Hostname changed to 'iotpilot'"
  fi
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

# Install Tailscale if auth key is provided
install_tailscale() {
  if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    info "Installing Tailscale..."

    # Check if Tailscale is already installed
    if command -v tailscale &> /dev/null; then
      info "Tailscale is already installed"
    else
      # Install Tailscale
      curl -fsSL https://tailscale.com/install.sh | sh || warn "Failed to install Tailscale"
    fi

    # Always force logout of any existing session first
    info "Logging out of any existing Tailscale sessions..."
    tailscale logout 2>/dev/null || true

    # Clean auth key - remove any whitespace, quotes, etc.
    CLEAN_AUTH_KEY=$(echo "$TAILSCALE_AUTH_KEY" | tr -d '[:space:]' | tr -d '"' | tr -d "'")

    info "Starting Tailscale with provided auth key..."

    # More robust command with explicit flags
    tailscale up --authkey="$CLEAN_AUTH_KEY" --hostname="iotpilot" --reset || {
      warn "Failed to authenticate Tailscale with provided key"
      warn "Will attempt alternative method..."

      # Try one more time with direct key writing to avoid any environment variable issues
      AUTH_KEY_FILE=$(mktemp)
      echo "$CLEAN_AUTH_KEY" > "$AUTH_KEY_FILE"
      FULL_AUTH_KEY=$(cat "$AUTH_KEY_FILE")
      tailscale up --authkey="$FULL_AUTH_KEY" --hostname="iotpilot" --reset || warn "All authentication attempts failed"
      rm -f "$AUTH_KEY_FILE"
    }

    # Give Tailscale a moment to establish connection
    info "Waiting for Tailscale to establish connection..."
    sleep 10

    # Get the Tailscale domain
    TAILSCALE_INFO=$(tailscale status --json)

    # Get DNSName directly instead of constructing it
    TAILSCALE_FQDN=$(echo "$TAILSCALE_INFO" | jq -r '.Self.DNSName' | sed 's/\.$//')

    if [ -n "$TAILSCALE_FQDN" ] && [ "$TAILSCALE_FQDN" != "null" ]; then
      info "Tailscale domain: $TAILSCALE_FQDN"

      # Save the Tailscale FQDN to the .env file
      if [ -f /opt/iotpilot/.env ]; then
        # Remove any existing TAILSCALE_DOMAIN settings
        sed -i '/TAILSCALE_DOMAIN=/d' /opt/iotpilot/.env
        # Add the new TAILSCALE_DOMAIN
        echo "TAILSCALE_DOMAIN=$TAILSCALE_FQDN" >> /opt/iotpilot/.env
        info "Added Tailscale domain to .env file"
      fi
    else
      warn "Could not determine Tailscale domain"
    fi
  else
    info "No Tailscale auth key provided, skipping Tailscale installation"
  fi
}

setup_tailscale_autofix() {
    info "Setting up automatic Tailscale domain configuration for Traefik..."

    # Make the script executable
    chmod +x /opt/iotpilot/scripts/tailscale-traefik-autofix.sh

    # Copy the systemd service file from the repository to systemd directory
    cp /opt/iotpilot/scripts/tailscale-traefik-autofix.service /etc/systemd/system/ 2>/dev/null || \
    error "Could not find tailscale-traefik-autofix.service in the repository"

    # Copy the systemd timer file from the repository to systemd directory
    cp /opt/iotpilot/scripts/tailscale-traefik-autofix.timer /etc/systemd/system/ 2>/dev/null || \
    error "Could not find tailscale-traefik-autofix.timer in the repository"

    # Enable and start the timer
    systemctl daemon-reload
    systemctl enable tailscale-traefik-autofix.timer
    systemctl start tailscale-traefik-autofix.timer

    # Run the script once to fix initial configuration
    /opt/iotpilot/scripts/tailscale-traefik-autofix.sh

    info "Tailscale auto-fix service installed and configured"
}

# Configure mDNS for local hostname resolution
setup_mdns() {
  info "Setting up mDNS for local hostname resolution..."

  # Configure Avahi
  if [ -f /etc/avahi/avahi-daemon.conf ]; then
    # Make sure .local is used and hostname is not changed
    sed -i 's/#domain-name=.*/domain-name=local/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#host-name=.*/host-name=iotpilot/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#publish-hinfo=.*/publish-hinfo=yes/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#publish-addresses=.*/publish-addresses=yes/' /etc/avahi/avahi-daemon.conf

    info "Configured Avahi daemon for mDNS"
  else
    warn "Avahi configuration file not found. Skipping mDNS configuration."
  fi

  # Restart Avahi to apply changes
  systemctl restart avahi-daemon || warn "Failed to restart Avahi daemon"

  # Verify mDNS is working
  info "mDNS setup complete. It may take a moment for 'iotpilot.local' to become available on your network."
}

# Install Traefik as a reverse proxy
install_traefik() {
  info "Installing and configuring Traefik as reverse proxy..."

  # Create directory for Traefik configuration
  mkdir -p /etc/traefik/config/certs

  # Generate self-signed certificates first
  info "Generating self-signed SSL certificates..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/traefik/config/certs/local-key.pem \
    -out /etc/traefik/config/certs/local-cert.pem \
    -subj "/CN=iotpilot.local/O=IoT Pilot/C=US" \
    -addext "subjectAltName = DNS:iotpilot.local,DNS:*.iotpilot.local,IP:127.0.0.1" \
    || warn "Certificate generation failed, continuing anyway"

  # Set permissions
  chmod 600 /etc/traefik/config/certs/local-key.pem
  chmod 644 /etc/traefik/config/certs/local-cert.pem

  # Create ACME directory
  mkdir -p /etc/traefik/acme

  # Create main Traefik configuration file
  cat > /etc/traefik/traefik.yml << EOL
api:
  insecure: true  # Enable the dashboard (set to false in production)
  dashboard: true

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
    http:
      tls:
        domains:
          - main: "iotpilot.local"
            sans:
              - "*.iotpilot.local"
          - main: "${TAILSCALE_FQDN:-}"
            sans:
              - "*.${TAILSCALE_FQDN:-}"

providers:
  file:
    directory: /etc/traefik/config/
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${ACME_EMAIL:-contact@iotpilot.local}"
      storage: /etc/traefik/acme/acme.json
      tlsChallenge: {}

# Enable access logs
accessLog: {}

# Log level
log:
  level: "INFO"
EOL

  # Create local certificates configuration
  cat > /etc/traefik/config/local.yml << EOL
tls:
  certificates:
    - certFile: /etc/traefik/config/certs/local-cert.pem
      keyFile: /etc/traefik/config/certs/local-key.pem
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/config/certs/local-cert.pem
        keyFile: /etc/traefik/config/certs/local-key.pem
EOL

  # Create dynamic configuration for IotPilot service
  cat > /etc/traefik/config/iotpilot.yml << EOL
http:
  routers:
    iotpilot-http:
      rule: "Host(\`iotpilot.local\`)"
      entrypoints:
        - web
      service: iotpilot
      priority: 100

    iotpilot-https:
      rule: "Host(\`iotpilot.local\`)"
      entrypoints:
        - websecure
      service: iotpilot
      tls: true
      priority: 100
EOL

# Only append this router if TAILSCALE_FQDN is set
if [ -n "$TAILSCALE_FQDN" ]; then
  cat >> /etc/traefik/config/iotpilot.yml << EOL
    iotpilot-tailscale:
      rule: "Host(\`$TAILSCALE_FQDN\`)"
      entrypoints:
        - websecure
      service: iotpilot
      tls: true
EOL
fi

# Finish with services block
cat >> /etc/traefik/config/iotpilot.yml << EOL

  services:
    iotpilot:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:4000"
EOL

  # Download Traefik binary for ARM64
  info "Downloading Traefik for ARM64 architecture..."
  TRAEFIK_VERSION="v2.10.5"

  # Use arm64 architecture for Traefik download
  ARCH=$(uname -m)
  if [[ "$ARCH" == "aarch64" ]]; then
    TRAEFIK_ARCH="arm64"  # Use arm64 for aarch64/ARM64
  else
    warn "Expected aarch64 architecture but found $ARCH - trying arm64 binary anyway"
    TRAEFIK_ARCH="arm64"
  fi

  info "Using architecture: $TRAEFIK_ARCH for Traefik download"
  if [ -f /usr/local/bin/traefik ]; then
    info "Traefik is already installed"
  else
    info "Downloading Traefik $TRAEFIK_VERSION for $TRAEFIK_ARCH..."
    curl -L "https://github.com/traefik/traefik/releases/download/${TRAEFIK_VERSION}/traefik_${TRAEFIK_VERSION}_linux_${TRAEFIK_ARCH}.tar.gz" -o /tmp/traefik.tar.gz || error "Failed to download Traefik"
    tar -xzf /tmp/traefik.tar.gz -C /tmp
    mv /tmp/traefik /usr/local/bin/
    chmod +x /usr/local/bin/traefik
    rm /tmp/traefik.tar.gz
  fi

  # Create systemd service for Traefik
  cat > /etc/systemd/system/traefik.service << EOL
[Unit]
Description=Traefik
Documentation=https://docs.traefik.io
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/traefik --configfile=/etc/traefik/traefik.yml
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOL

  # Start and enable Traefik service
  systemctl daemon-reload
  systemctl enable traefik.service
  systemctl restart traefik.service || warn "Failed to start Traefik service"

  info "Traefik configured successfully. Dashboard available at http://iotpilot.local:8080"
}

# Clone the repository and install dependencies
setup_application() {
  local repo_dir="/opt/iotpilot"

  info "Setting up IotPilot application..."

  # Create application user (non-root)
  if ! id -u iotpilot &>/dev/null; then
    useradd -m -s /bin/bash iotpilot || warn "Failed to create iotpilot user"
  fi

  # Clone or update repository
  if [ -d "$repo_dir" ]; then
    info "Repository already exists, updating..."
    cd "$repo_dir"

    # First stash any local changes to avoid merge conflicts
    git config --global --add safe.directory "$repo_dir"
    git stash || warn "Failed to stash local changes"
    git pull || warn "Failed to update repository"
  else
    # Make directory writable (in case it exists but isn't writable)
    mkdir -p "$repo_dir" || true
    chmod 755 "$repo_dir" || true

    info "Cloning repository..."
    git clone https://github.com/andrerfz/iotpilot.git "$repo_dir" || error "Failed to clone repository"
    cd "$repo_dir"
  fi

  # Create data directory
  mkdir -p "$repo_dir/app/data"

  # Set up environment file
  if [ ! -f "$repo_dir/.env" ]; then
      cp "$repo_dir/.env.example" "$repo_dir/.env" || warn "Failed to create .env file"
      sed -i "s/HOST_NAME=.*/HOST_NAME=iotpilot.local/" "$repo_dir/.env"

      # Add Tailscale domain if available
      if [ -n "$TAILSCALE_FQDN" ]; then
          echo "TAILSCALE_DOMAIN=$TAILSCALE_FQDN" >> "$repo_dir/.env"
      fi

      # Add Tailscale Auth Key if provided
      if [ -n "$TAILSCALE_AUTH_KEY" ]; then
          echo "TAILSCALE_AUTH_KEY=$TAILSCALE_AUTH_KEY" >> "$repo_dir/.env"
          echo "Added Tailscale Auth Key to .env file"
      fi
  fi

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

  info "Application setup completed successfully"
}

# Create systemd service for auto-start on boot
create_systemd_service() {
  info "Creating systemd service for IotPilot..."

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

  # Create service file with path to our installed Node.js binary
  # Using modern systemd logging (no syslog)
  cat > /etc/systemd/system/iotpilot.service << EOL
[Unit]
Description=IotPilot IoT Device Management
After=network.target traefik.service avahi-daemon.service
Wants=traefik.service avahi-daemon.service

[Service]
Type=simple
User=iotpilot
WorkingDirectory=/opt/iotpilot/app
ExecStart=${NODE_PATH} server.js
Restart=always
RestartSec=10
# Modern logging configuration (no syslog)
StandardOutput=journal
StandardError=journal
SyslogIdentifier=iotpilot
Environment=NODE_ENV=production
Environment=HOST_NAME=iotpilot.local

[Install]
WantedBy=multi-user.target
EOL

  # Reload systemd, enable and start the service
  systemctl daemon-reload
  systemctl enable iotpilot.service
  systemctl start iotpilot.service || warn "Failed to start iotpilot service"

  info "Systemd service created and enabled"
}

# Display final information
show_information() {
  echo
  echo -e "${GREEN}=============================================${NC}"
  echo -e "${GREEN}     IotPilot Pi 3 Installation Complete     ${NC}"
  echo -e "${GREEN}=============================================${NC}"
  echo
  echo "Your IotPilot instance is now running!"
  echo
  echo "Access your installation at:"
  echo "  - HTTP: http://iotpilot.local"
  echo "  - HTTPS: https://iotpilot.local"
  echo "  - Traefik Dashboard: http://iotpilot.local:8080"
  echo
  echo "API documentation is available at:"
  echo "  - http://iotpilot.local/api-docs"
  echo

  if [ -n "$TAILSCALE_FQDN" ]; then
    echo "Tailscale access:"
    echo "  - https://$TAILSCALE_FQDN"
    echo
  fi

  echo "The installation directory is: /opt/iotpilot"
  echo
  echo "Useful commands:"
  echo "  - systemctl status iotpilot  : Check service status"
  echo "  - systemctl restart iotpilot : Restart the service"
  echo "  - journalctl -u iotpilot     : View logs"
  echo
  echo "mDNS has been configured, so any device on your local network"
  echo "should be able to access your server using iotpilot.local"
  echo
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
  setup_application
  create_systemd_service
  setup_tailscale_autofix
  show_information
}

# Run the main installation function
main

exit 0