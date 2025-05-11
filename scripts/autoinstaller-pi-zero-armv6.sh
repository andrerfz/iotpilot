#!/bin/bash

# IotPilot Raspberry Pi Zero W Rev 1.1 Installer
# This script installs IotPilot directly on a Raspberry Pi Zero W Rev 1.1 running Debian Bookworm
# Usage:
#   sudo apt install curl
#   Basic: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero-armv6.sh | sudo bash
#   With Tailscale key: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero-armv6.sh | sudo TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash

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
  cd "$TEMP_DIR"

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
  cd /
  rm -rf "$TEMP_DIR"

  # Verify installation
  if ! /usr/local/bin/node --version; then
    error "Node.js installation failed"
  fi

  # Install nodemon globally
  /usr/local/bin/npm install -g nodemon || warn "Failed to install nodemon globally"

  info "Node.js v${NODE_VERSION} installed successfully"
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

    # Save the auth key to a file to ensure it's not truncated
    AUTH_KEY_FILE=$(mktemp)
    echo "$TAILSCALE_AUTH_KEY" > "$AUTH_KEY_FILE"
    FULL_AUTH_KEY=$(cat "$AUTH_KEY_FILE")

    # Start Tailscale with the provided auth key
    info "Starting Tailscale with provided auth key..."
    tailscale up --authkey="$FULL_AUTH_KEY" --hostname="iotpilot" || warn "Failed to authenticate Tailscale"

    # Clean up the temporary file
    rm -f "$AUTH_KEY_FILE"

    # Give Tailscale a moment to establish connection
    sleep 5

    # Get the Tailscale domain
    TAILSCALE_INFO=$(tailscale status --json)
    TAILSCALE_DOMAIN=$(echo "$TAILSCALE_INFO" | jq -r '.MagicDNSSuffix')
    TAILSCALE_HOSTNAME=$(hostname)

    if [ -n "$TAILSCALE_DOMAIN" ] && [ "$TAILSCALE_DOMAIN" != "null" ]; then
      TAILSCALE_FQDN="${TAILSCALE_HOSTNAME}.${TAILSCALE_DOMAIN}"
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

  # Download Traefik binary
  info "Downloading Traefik..."
  TRAEFIK_VERSION="v2.10.5"

  # Determine architecture
  if [ "$(uname -m)" = "armv6l" ]; then
    ARCH="armv6"
  elif [ "$(uname -m)" = "armv7l" ]; then
    ARCH="armv7"
  else
    # Default to armv6 for Raspberry Pi Zero
    ARCH="armv6"
  fi

  info "Using architecture: $ARCH for Traefik download"
  if [ -f /usr/local/bin/traefik ]; then
    info "Traefik is already installed"
  else
    curl -L "https://github.com/traefik/traefik/releases/download/${TRAEFIK_VERSION}/traefik_${TRAEFIK_VERSION}_linux_${ARCH}.tar.gz" -o /tmp/traefik.tar.gz || error "Failed to download Traefik"
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

  # Use pre-compiled node_modules for Pi Zero (ARMv6)
  if [ "$IS_PI_ZERO" = true ]; then
    info "Using pre-compiled node_modules for Raspberry Pi Zero..."

    cd "$repo_dir"

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
    cd "$repo_dir/app"
    info "Installing Node.js dependencies (this may take a while)..."

    # Use the installed node and npm from our binary installation
    NODE_BIN="/usr/local/bin/node"
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

  info "Application setup completed successfully"
}

# Create systemd service for auto-start on boot
create_systemd_service() {
  info "Creating systemd service for IotPilot..."

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
ExecStart=/usr/local/bin/node server.js
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
  systemctl restart iotpilot.service

  info "Systemd service created and enabled"
}

# Display final information
show_information() {
  echo
  echo -e "${GREEN}=============================================${NC}"
  echo -e "${GREEN}     IotPilot Pi Zero Installation Complete   ${NC}"
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
  setup_application
  create_systemd_service
  show_information
}

# Run the main installation function
main

exit 0