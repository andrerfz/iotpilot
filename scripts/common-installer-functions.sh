#!/bin/bash

# Common installer functions for IotPilot
# This script contains functions shared between the Pi 3 and Pi Zero installers

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
check_root() {
  if [ "$EUID" -ne 0 ]; then
    error "Please run as root (sudo)"
  fi
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

    # Use custom hostname if provided, otherwise default to "iotpilot"
    TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-"iotpilot"}
    info "Starting Tailscale with provided auth key and hostname: $TAILSCALE_HOSTNAME..."

    # More robust command with explicit flags
    tailscale up --authkey="$CLEAN_AUTH_KEY" --hostname="$TAILSCALE_HOSTNAME" --reset || {
      warn "Failed to authenticate Tailscale with provided key"
      warn "Will attempt alternative method..."

      # Try one more time with direct key writing to avoid any environment variable issues
      AUTH_KEY_FILE=$(mktemp)
      echo "$CLEAN_AUTH_KEY" > "$AUTH_KEY_FILE"
      FULL_AUTH_KEY=$(cat "$AUTH_KEY_FILE")
      tailscale up --authkey="$FULL_AUTH_KEY" --hostname="$TAILSCALE_HOSTNAME" --reset || warn "All authentication attempts failed"
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

# Setup Tailscale autofix service and timer
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

  # 1. Check if systemd-resolved is running and conflicts with Avahi
  if systemctl is-active systemd-resolved >/dev/null 2>&1; then
    warn "systemd-resolved is running, which may conflict with Avahi"
    info "Configuring systemd-resolved to work with Avahi..."

    # Configure systemd-resolved to not handle .local domains
    mkdir -p /etc/systemd/resolved.conf.d
    cat > /etc/systemd/resolved.conf.d/avahi.conf << 'EOF'
[Resolve]
MulticastDNS=no
LLMNR=no
EOF
    systemctl restart systemd-resolved || warn "Failed to restart systemd-resolved"
  fi

  # 2. Install required packages if not present
  info "Ensuring mDNS packages are installed..."
  if ! dpkg -l | grep -q libnss-mdns; then
    apt-get update -qq
    apt-get install -y libnss-mdns avahi-utils || warn "Failed to install mDNS packages"
  fi

  # 3. Configure Avahi (more conservative approach)
  if [ -f /etc/avahi/avahi-daemon.conf ]; then
    info "Configuring Avahi daemon..."

    # Backup original config
    cp /etc/avahi/avahi-daemon.conf /etc/avahi/avahi-daemon.conf.backup 2>/dev/null || true

    # Apply key settings without overwriting entire file
    sed -i 's/#host-name=.*/host-name=iotpilot/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#domain-name=.*/domain-name=local/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#publish-addresses=.*/publish-addresses=yes/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#publish-hinfo=.*/publish-hinfo=yes/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#publish-workstation=.*/publish-workstation=yes/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#use-ipv6=.*/use-ipv6=no/' /etc/avahi/avahi-daemon.conf

    # Only deny Docker interfaces if they exist
    if ip link show | grep -q docker; then
      sed -i 's/#deny-interfaces=.*/deny-interfaces=docker0,br-*,veth*/' /etc/avahi/avahi-daemon.conf
    fi

    info "Applied Avahi configuration changes"
  else
    warn "Avahi configuration file not found, using defaults"
  fi

  # 4. Fix /etc/nsswitch.conf for proper resolution order (safely)
  info "Configuring name resolution order..."
  if [ -f /etc/nsswitch.conf ]; then
    cp /etc/nsswitch.conf /etc/nsswitch.conf.backup
    if grep -q "hosts:" /etc/nsswitch.conf; then
      # Only modify if mdns4_minimal isn't already there
      if ! grep "hosts:" /etc/nsswitch.conf | grep -q mdns4_minimal; then
        sed -i 's/hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
        info "Updated nsswitch.conf for mDNS resolution"
      fi
    fi
  fi

  # 5. Clean hostname setup (safer approach)
  info "Ensuring clean hostname configuration..."
  CURRENT_HOSTNAME=$(hostname)

  if [ "$CURRENT_HOSTNAME" != "iotpilot" ]; then
    info "Setting hostname to iotpilot..."
    hostnamectl set-hostname iotpilot

    # Update /etc/hosts carefully
    if [ -f /etc/hosts ]; then
      cp /etc/hosts /etc/hosts.backup
      # Remove old hostname entries, keep localhost
      sed -i "/127.0.1.1.*${CURRENT_HOSTNAME}/d" /etc/hosts

      # Add iotpilot if not already present
      if ! grep -q "127.0.1.1.*iotpilot" /etc/hosts; then
        echo "127.0.1.1 iotpilot" >> /etc/hosts
      fi
    fi
  fi

  # 6. Restart Avahi and verify
  info "Restarting Avahi daemon..."
  systemctl restart avahi-daemon || warn "Failed to restart Avahi daemon"

  # Wait for Avahi to stabilize
  sleep 3

  # 7. Simple verification
  info "Verifying mDNS setup..."
  if command -v avahi-resolve >/dev/null 2>&1; then
    if timeout 5 avahi-resolve -n iotpilot.local >/dev/null 2>&1; then
      info "✓ mDNS resolution working"
    else
      warn "✗ mDNS resolution test failed - may take time to propagate"
    fi
  fi

  # 8. Create simple IP change monitor (optional, safer)
  info "Setting up IP change monitoring..."
  cat > /usr/local/bin/iotpilot-mdns-refresh.sh << 'EOF'
#!/bin/bash
# Simple script to refresh mDNS when IP changes

CURRENT_IP=$(hostname -I | awk '{print $1}')
LAST_IP_FILE="/var/tmp/iotpilot-last-ip"

if [ -f "$LAST_IP_FILE" ]; then
    LAST_IP=$(cat "$LAST_IP_FILE")
    if [ "$CURRENT_IP" != "$LAST_IP" ] && [ -n "$CURRENT_IP" ]; then
        logger "IoTPilot: IP changed from $LAST_IP to $CURRENT_IP, refreshing mDNS"
        systemctl restart avahi-daemon
    fi
fi

echo "$CURRENT_IP" > "$LAST_IP_FILE"
EOF

  chmod +x /usr/local/bin/iotpilot-mdns-refresh.sh

  # Add to cron (check every 5 minutes)
  if ! crontab -l 2>/dev/null | grep -q iotpilot-mdns-refresh; then
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/iotpilot-mdns-refresh.sh >/dev/null 2>&1") | crontab -
    info "Added IP monitoring to cron"
  fi

  info "mDNS setup complete"
  info "Device should be accessible as 'iotpilot.local' on your network"
  info "Note: Some routers may block mDNS traffic - if issues persist, use direct IP"
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

  # Download Traefik binary based on architecture
  info "Downloading Traefik for the current architecture..."
  TRAEFIK_VERSION="v2.10.5"

  # Determine architecture
  ARCH=$(uname -m)
  if [[ "$ARCH" == "aarch64" ]]; then
    TRAEFIK_ARCH="arm64"
  elif [[ "$ARCH" == "armv6l" ]]; then
    TRAEFIK_ARCH="armv6"
  elif [[ "$ARCH" == "armv7l" ]]; then
    TRAEFIK_ARCH="armv7"
  else
    warn "Unexpected architecture: $ARCH - trying to determine best match"
    # Default to armv6 for compatibility
    TRAEFIK_ARCH="armv6"
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
    cd "$repo_dir" || return 1

    # First stash any local changes to avoid merge conflicts
    git config --global --add safe.directory "$repo_dir"
    git stash || warn "Failed to stash local changes"
    git fetch origin || warn "Failed to fetch from remote"
    git checkout "${IOTPILOT_BRANCH:-main}" || git checkout -b "${IOTPILOT_BRANCH:-main}" "origin/${IOTPILOT_BRANCH:-main}" || warn "Failed to checkout branch ${IOTPILOT_BRANCH:-main}"
    git pull origin "${IOTPILOT_BRANCH:-main}" || warn "Failed to update repository"
  else
    # Make directory writable (in case it exists but isn't writable)
    mkdir -p "$repo_dir" || true
    chmod 755 "$repo_dir" || true

    info "Cloning repository..."
    git clone --branch "${IOTPILOT_BRANCH:-main}" https://github.com/andrerfz/iotpilot.git "$repo_dir" || error "Failed to clone repository"
    cd "$repo_dir" || return 1
  fi

  # Create data directory
  mkdir -p "$repo_dir/app/data"

  # Set up environment file. This block runs only on fresh installs (.env
  # missing). On updates, the existing .env is left untouched so upgrading
  # Pis keep their current auth state.
  if [ ! -f "$repo_dir/.env" ]; then
      cp "$repo_dir/.env.example" "$repo_dir/.env" || warn "Failed to create .env file"
      sed -i "s/HOST_NAME=.*/HOST_NAME=iotpilot.local/" "$repo_dir/.env"

      # Enable auth by default for fresh installs, with a random session secret.
      sed -i "s/^AUTH_ENABLED=.*/AUTH_ENABLED=true/" "$repo_dir/.env"
      SESSION_SECRET_VALUE=$(openssl rand -base64 48 | tr -d '\n')
      sed -i "s|^SESSION_SECRET=.*|SESSION_SECRET=$SESSION_SECRET_VALUE|" "$repo_dir/.env"
      info "Auth enabled by default (log in at /login with user 'admin' and the master password)"

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

  # Note: Node.js dependencies installation is handled by the specific installer scripts
  # as it's architecture-dependent

  info "Application setup completed successfully"
}

# Create systemd service for auto-start on boot
create_systemd_service() {
  info "Creating systemd service for IotPilot..."

  # Find node executable path - this should be provided by the specific installer
  NODE_PATH=${NODE_PATH:-$(which node)}

  if [ -z "$NODE_PATH" ]; then
    error "Could not find Node.js executable. Please install Node.js and try again."
    return 1
  fi

  info "Using Node.js from: $NODE_PATH"

  # Create service file with path to our installed Node.js binary
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
  systemctl restart iotpilot.service || warn "Failed to start iotpilot service"

  info "Systemd service created and enabled"
}

# Display final information
show_information() {
  local pi_model=$1

  echo
  echo -e "${GREEN}=============================================${NC}"
  echo -e "${GREEN}     IotPilot ${pi_model} Installation Complete     ${NC}"
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
