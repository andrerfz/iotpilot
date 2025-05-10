#!/bin/bash

# IotPilot Raspberry Pi Zero 2W Installer
# This script installs IotPilot directly on a Raspberry Pi Zero 2W running Debian Bookworm
# Usage:
#   Basic: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero.sh | sudo bash
#   With Tailscale key: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero.sh | sudo TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash

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
if [ ! -f /proc/device-tree/model ]; then
  warn "Could not detect Raspberry Pi model. Installation might not work correctly."
  IS_RASPBERRY=false
else
  MODEL=$(tr -d '\0' < /proc/device-tree/model)
  info "Detected: $MODEL"
  if [[ "$MODEL" == *"Raspberry Pi"* ]]; then
    IS_RASPBERRY=true
    info "Raspberry Pi detected - will use specialized configuration"
  else
    IS_RASPBERRY=false
    warn "This doesn't appear to be a Raspberry Pi. Will use standard configuration."
  fi
fi

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
    || error "Failed to install required system packages"
}

# Fix hostname resolution issues
fix_hostname_resolution() {
  info "Fixing hostname resolution..."

  # Set hostname to iotpilot if not already set
  CURRENT_HOSTNAME=$(hostname)
  if [ "$CURRENT_HOSTNAME" != "iotpilot" ]; then
    hostnamectl set-hostname iotpilot || warn "Failed to set hostname to iotpilot"
    info "Hostname set to iotpilot"
  else
    info "Hostname is already set to iotpilot"
  fi

  # Fix /etc/hosts to ensure proper hostname resolution
  if grep -q "127.0.1.1.*iotpilot" /etc/hosts; then
    info "Hosts file is properly configured"
  else
    # Remove any existing 127.0.1.1 entries
    sed -i '/127.0.1.1/d' /etc/hosts
    # Add correct entry
    echo "127.0.1.1       iotpilot" >> /etc/hosts
    info "Updated hosts file with correct hostname entry"
  fi
}

# Install Node.js 20
install_nodejs() {
  info "Installing Node.js 20..."

  # Check if Node.js is already installed and at right version
  if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    if [[ "$NODE_VERSION" == "v20"* ]]; then
      info "Node.js v20 is already installed: $NODE_VERSION"
      return 0
    else
      info "Node.js $NODE_VERSION is installed, but v20 is required. Will update."
      # Remove existing Node.js
      apt-get remove -y nodejs npm || warn "Failed to remove existing Node.js"
      # Clean up repositories
      rm -f /etc/apt/sources.list.d/nodesource*.list
    fi
  fi

  # Install Node.js 20
  info "Setting up NodeSource repository..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || error "Failed to setup Node.js repository"

  info "Installing Node.js 20..."
  apt-get install -y nodejs || error "Failed to install Node.js"

  # Verify installation
  NODE_VERSION=$(node --version)
  NPM_VERSION=$(npm --version)
  info "Node.js $NODE_VERSION and npm $NPM_VERSION installed successfully"

  # Install nodemon globally
  npm install -g nodemon || warn "Failed to install nodemon globally"
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

    # Start Tailscale with the provided auth key
    info "Starting Tailscale with provided auth key..."
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname="iotpilot" || warn "Failed to authenticate Tailscale"

    # Get the Tailscale domain
    TAILSCALE_INFO=$(tailscale status --json)
    TAILSCALE_DOMAIN=$(echo "$TAILSCALE_INFO" | jq -r '.MagicDNSSuffix')
    TAILSCALE_HOSTNAME=$(hostname)

    if [ -n "$TAILSCALE_DOMAIN" ] && [ "$TAILSCALE_DOMAIN" != "null" ]; then
      TAILSCALE_FQDN="${TAILSCALE_HOSTNAME}.${TAILSCALE_DOMAIN}"
      info "Tailscale domain: $TAILSCALE_FQDN"
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
  if ping -c 1 iotpilot.local &>/dev/null; then
    info "mDNS setup verified: iotpilot.local is reachable!"
  else
    warn "mDNS setup might not be working. Devices may need time to discover the service."
  fi
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

    iotpilot-https:
      rule: "Host(\`iotpilot.local\`)"
      entrypoints:
        - websecure
      service: iotpilot
      tls: true
EOL

  # If Tailscale domain is available, add it to configuration
  if [ -n "$TAILSCALE_FQDN" ]; then
    cat >> /etc/traefik/config/iotpilot.yml << EOL

    iotpilot-tailscale:
      rule: "Host(\`${TAILSCALE_FQDN}\`)"
      entrypoints:
        - websecure
      service: iotpilot
      tls: true
EOL
  fi

  # Complete the service definition
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
  fi

  # Install Node.js dependencies with retry and verbose output
  cd "$repo_dir/app"
  info "Installing Node.js dependencies (this may take a while)..."
  # Try up to 3 times to install dependencies
  for i in {1..3}; do
    info "Dependency installation attempt $i..."
    npm install --unsafe-perm || {
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

  # Fix permissions
  chown -R iotpilot:iotpilot "$repo_dir"
  chmod -R 755 "$repo_dir"

  info "Application setup completed successfully"
}

# Create systemd service for auto-start on boot
create_systemd_service() {
  info "Creating systemd service for IotPilot..."

  # Create service file
  cat > /etc/systemd/system/iotpilot.service << EOL
[Unit]
Description=IotPilot IoT Device Management
After=network.target traefik.service avahi-daemon.service
Wants=traefik.service avahi-daemon.service

[Service]
Type=simple
User=iotpilot
WorkingDirectory=/opt/iotpilot/app
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=iotpilot
Environment=NODE_ENV=production
Environment=HOST_NAME=iotpilot.local

[Install]
WantedBy=multi-user.target
EOL

  # Reload systemd, enable and start the service
  systemctl daemon-reload
  systemctl enable iotpilot.service
  systemctl start iotpilot.service

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