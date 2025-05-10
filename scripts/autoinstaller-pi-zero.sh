#!/bin/bash

# IotPilot Raspberry Pi Zero 2W Installer
# This script installs IotPilot directly on a Raspberry Pi Zero 2W running Debian Bookworm
# Usage: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/iotpilot-pi-zero-install.sh | sudo bash

set -e

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Log functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
  exit 1
}

# Confirm running as root
if [ "$EUID" -ne 0 ]; then
  log_error "Please run as root (sudo)"
fi

# Get Pi model information
PI_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "Unknown")
log_info "Detected hardware: $PI_MODEL"

# Check if this is a Raspberry Pi Zero 2W
if [[ "$PI_MODEL" != *"Raspberry Pi Zero 2"* ]]; then
  log_warn "This script is optimized for Raspberry Pi Zero 2W but will attempt to continue."
fi

# Installation directory
INSTALL_DIR="/opt/iotpilot"
DATA_DIR="$INSTALL_DIR/data"
CERT_DIR="$INSTALL_DIR/certs"
CONFIG_DIR="$INSTALL_DIR/config"

# Installation steps
setup_system() {
  log_info "Updating system and installing dependencies..."
  apt-get update
  apt-get install -y git curl gnupg apt-transport-https ca-certificates lsb-release \
    jq wget net-tools python3-pip avahi-daemon

  # Fix hostname resolution with mDNS
  log_info "Configuring hostname as 'iotpilot'..."
  hostnamectl set-hostname iotpilot

  # Update /etc/hosts
  if ! grep -q "iotpilot" /etc/hosts; then
    sed -i '/127.0.1.1/d' /etc/hosts
    echo "127.0.1.1       iotpilot.local iotpilot" >> /etc/hosts
    log_info "Updated /etc/hosts"
  fi

  # Configure Avahi for mDNS
  if [ -f /etc/avahi/avahi-daemon.conf ]; then
    sed -i 's/#domain-name=.*/domain-name=local/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#host-name=.*/host-name=iotpilot/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#publish-hinfo=.*/publish-hinfo=yes/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#publish-addresses=.*/publish-addresses=yes/' /etc/avahi/avahi-daemon.conf
    log_info "Configured Avahi daemon for mDNS"
  fi

  # Restart Avahi
  systemctl restart avahi-daemon
  log_info "System basic setup completed"
}

install_nodejs() {
  log_info "Installing Node.js..."

  # Check if Node.js is already installed
  if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v)
    log_info "Node.js $NODE_VERSION is already installed"
  else
    # Install Node.js 18.x (compatible with the project)
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    # Verify installation
    NODE_VERSION=$(node -v)
    NPM_VERSION=$(npm -v)
    log_info "Successfully installed Node.js $NODE_VERSION with NPM $NPM_VERSION"
  fi
}

install_traefik() {
  log_info "Installing Traefik..."

  # Create Traefik directory
  mkdir -p $CONFIG_DIR/traefik
  mkdir -p $CERT_DIR

  # Download the Traefik binary
  TRAEFIK_VERSION="v2.10.7"
  if [ ! -f /usr/local/bin/traefik ]; then
    log_info "Downloading Traefik $TRAEFIK_VERSION..."
    wget -q -O /tmp/traefik.tar.gz https://github.com/traefik/traefik/releases/download/$TRAEFIK_VERSION/traefik_${TRAEFIK_VERSION}_linux_armv7.tar.gz
    tar -xzf /tmp/traefik.tar.gz -C /tmp
    mv /tmp/traefik /usr/local/bin/
    chmod +x /usr/local/bin/traefik
    rm /tmp/traefik.tar.gz
    log_info "Traefik installed to /usr/local/bin/traefik"
  else
    log_info "Traefik is already installed"
  fi

  # Create Traefik configuration
  cat > $CONFIG_DIR/traefik/traefik.yml << EOL
api:
  insecure: true
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

providers:
  file:
    directory: $CONFIG_DIR/traefik/config
    watch: true

# Enable access logs
accessLog: {}

# Log level
log:
  level: "INFO"
EOL

  # Create TLS configuration
  mkdir -p $CONFIG_DIR/traefik/config
  cat > $CONFIG_DIR/traefik/config/local.yml << EOL
tls:
  certificates:
    - certFile: $CERT_DIR/local-cert.pem
      keyFile: $CERT_DIR/local-key.pem
  stores:
    default:
      defaultCertificate:
        certFile: $CERT_DIR/local-cert.pem
        keyFile: $CERT_DIR/local-key.pem
EOL

  # Generate self-signed certificates
  log_info "Generating self-signed certificates..."
  if [ ! -f $CERT_DIR/local-cert.pem ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout $CERT_DIR/local-key.pem \
      -out $CERT_DIR/local-cert.pem \
      -subj "/CN=iotpilot.local/O=IoT Pilot/C=US" \
      -addext "subjectAltName = DNS:iotpilot.local,DNS:*.iotpilot.local,IP:127.0.0.1"

    chmod 644 $CERT_DIR/local-cert.pem
    chmod 600 $CERT_DIR/local-key.pem
    log_info "SSL certificates generated for iotpilot.local"
  else
    log_info "SSL certificates already exist"
  fi

  # Create Traefik service file
  cat > /etc/systemd/system/traefik.service << EOL
[Unit]
Description=Traefik Edge Router
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/traefik --configfile=$CONFIG_DIR/traefik/traefik.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

  # Enable and start Traefik
  systemctl daemon-reload
  systemctl enable traefik
  systemctl restart traefik
  log_info "Traefik installed and configured"
}

install_tailscale() {
  log_info "Installing Tailscale..."

  # Install Tailscale
  curl -fsSL https://tailscale.com/install.sh | sh

  # Create script to update environment with Tailscale domain
  cat > $INSTALL_DIR/update-tailscale-domain.sh << EOL
#!/bin/bash
# Script to update Tailscale domain in the .env file

ENV_FILE=$INSTALL_DIR/.env

# Get Tailscale status
TAILSCALE_INFO=\$(tailscale status --json)
if [ \$? -ne 0 ]; then
  echo "Error retrieving Tailscale information"
  exit 1
fi

# Extract the MagicDNSSuffix
TAILSCALE_DOMAIN=\$(echo "\$TAILSCALE_INFO" | jq -r '.MagicDNSSuffix')
if [ -z "\$TAILSCALE_DOMAIN" ] || [ "\$TAILSCALE_DOMAIN" = "null" ]; then
  echo "No Tailscale domain found. Tailscale may not be properly configured."
  exit 1
fi

# Get hostname
HOSTNAME=\$(hostname)
if [ -z "\$HOSTNAME" ]; then
  HOSTNAME="iotpilot"
fi

# Create full domain
FULL_DOMAIN="\${HOSTNAME}.\${TAILSCALE_DOMAIN}"

# Update .env file
if grep -q "TAILSCALE_DOMAIN=" \$ENV_FILE; then
  # Replace existing entry
  sed -i "s/TAILSCALE_DOMAIN=.*/TAILSCALE_DOMAIN=\${FULL_DOMAIN}/" \$ENV_FILE
  echo "Updated TAILSCALE_DOMAIN in .env to \${FULL_DOMAIN}"
else
  # Add new entry
  echo "TAILSCALE_DOMAIN=\${FULL_DOMAIN}" >> \$ENV_FILE
  echo "Added TAILSCALE_DOMAIN=\${FULL_DOMAIN} to .env file"
fi
EOL

  chmod +x $INSTALL_DIR/update-tailscale-domain.sh

  log_info "Tailscale installed. You can authenticate by running 'sudo tailscale up' manually."
  log_info "After authentication, run '$INSTALL_DIR/update-tailscale-domain.sh' to update your domain"
}

install_iotpilot() {
  log_info "Installing IotPilot application..."

  # Create installation directories
  mkdir -p $INSTALL_DIR
  mkdir -p $DATA_DIR

  # Clone the repository
  if [ -d "$INSTALL_DIR/app" ]; then
    log_info "Repository already exists, updating..."
    cd $INSTALL_DIR
    git pull
  else
    log_info "Cloning repository..."
    cd $INSTALL_DIR
    git clone https://github.com/andrerfz/iotpilot.git .
  fi

  # Create .env file from example
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    cp $INSTALL_DIR/.env.example $INSTALL_DIR/.env
    sed -i "s/HOST_NAME=.*/HOST_NAME=iotpilot.local/" $INSTALL_DIR/.env
    log_info "Created .env file with default settings"
  fi

  # Install dependencies
  log_info "Installing Node.js dependencies..."
  cd $INSTALL_DIR/app
  npm install

  # Create systemd service file for IotPilot
  cat > /etc/systemd/system/iotpilot.service << EOL
[Unit]
Description=IotPilot IoT Management Server
After=network.target
Wants=traefik.service
Requires=traefik.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/app
Environment=NODE_ENV=production
Environment=HOST_NAME=iotpilot.local
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

  # Enable and start IotPilot service
  systemctl daemon-reload
  systemctl enable iotpilot
  systemctl restart iotpilot

  log_info "IotPilot application installed and service started"
}

configure_nginx_proxy() {
  log_info "Setting up Nginx as a reverse proxy..."

  # Install Nginx
  apt-get install -y nginx

  # Create Nginx configuration for proxying to IotPilot
  cat > /etc/nginx/sites-available/iotpilot << EOL
server {
    listen 80;
    server_name iotpilot.local;

    location / {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

  # Enable site
  ln -sf /etc/nginx/sites-available/iotpilot /etc/nginx/sites-enabled/

  # Test and restart Nginx
  nginx -t && systemctl restart nginx

  log_info "Nginx configured as reverse proxy"
}

# Main installation
main() {
  log_info "Starting IotPilot installation for Raspberry Pi Zero 2W..."

  setup_system
  install_nodejs
  install_traefik
  install_tailscale
  install_iotpilot

  log_info "Installation complete!"
  log_info "Your IotPilot instance should be accessible at:"
  log_info "  - Local HTTP:  http://iotpilot.local"
  log_info "  - Local HTTPS: https://iotpilot.local"
  log_info "  - Traefik Dashboard: http://iotpilot.local:8080"

  log_info "To authenticate with Tailscale, run:"
  log_info "  sudo tailscale up"
  log_info "After authenticating, update your Tailscale domain with:"
  log_info "  sudo $INSTALL_DIR/update-tailscale-domain.sh"

  log_info "For any issues, check the logs with:"
  log_info "  sudo journalctl -u iotpilot -f"
  log_info "  sudo journalctl -u traefik -f"
}

# Run installation
main