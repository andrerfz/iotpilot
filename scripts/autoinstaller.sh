#!/bin/bash

# IotPilot Autoinstaller
# This script automates the installation of IotPilot on a new Raspberry Pi device
# Usage: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller.sh | sudo bash

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

# Install dependencies
install_dependencies() {
  info "Updating package lists..."
  apt-get update -y || error "Failed to update package lists"

  info "Installing required packages..."
  apt-get install -y \
    git \
    make \
    curl \
    docker.io \
    docker-compose \
    jq \
    avahi-daemon || error "Failed to install required packages"

  # Enable and start Docker service
  info "Enabling and starting Docker service..."
  systemctl enable docker
  systemctl start docker

  # Add current user to docker group to avoid using sudo with docker
  if [ "$SUDO_USER" ]; then
    info "Adding user $SUDO_USER to the docker group..."
    usermod -aG docker "$SUDO_USER"

    # Ensure the user has the right permissions immediately
    # This is needed for the current session
    if [ -S /var/run/docker.sock ]; then
      chmod 666 /var/run/docker.sock
      info "Set temporary permissions on docker.sock for immediate use"
    fi
  else
    warn "Could not determine the sudo user. You may need to add your user to the docker group manually."
  fi
}

# Configure mDNS for local hostname resolution
setup_mdns() {
  info "Setting up mDNS for local hostname resolution..."

  # Set hostname to iotpilot
  hostnamectl set-hostname iotpilot || warn "Failed to set hostname to iotpilot"

  # Update /etc/hosts to include hostname
  if grep -q "iotpilot" /etc/hosts; then
    info "Hostname already present in /etc/hosts"
  else
    # Add hostname to hosts file for local resolution
    sed -i '/127.0.1.1/d' /etc/hosts
    echo "127.0.1.1       iotpilot" >> /etc/hosts
    info "Added iotpilot to /etc/hosts"
  fi

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

# Clone the repository
clone_repository() {
  local repo_dir="/opt/iotpilot"

  if [ -d "$repo_dir" ]; then
    warn "Directory $repo_dir already exists"
    info "Removing existing installation..."
    rm -rf "$repo_dir"
  fi

  info "Cloning IotPilot repository to $repo_dir..."
  git clone https://github.com/andrerfz/iotpilot.git "$repo_dir" || error "Failed to clone repository"

  # Set correct ownership if we're running with sudo
  if [ "$SUDO_USER" ]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$repo_dir"
  fi

  cd "$repo_dir" || error "Failed to enter repository directory"
}

# Setup environment
setup_environment() {
  info "Setting up environment..."

  # Update the .env.example to ensure HOST_NAME is set to iotpilot.local
  if grep -q "HOST_NAME=" .env.example; then
    sed -i 's/HOST_NAME=.*/HOST_NAME=iotpilot.local/' .env.example
    info "Updated .env.example to use iotpilot.local as hostname"
  fi

  # Create .env file from example if it doesn't exist
  if [ ! -f .env ]; then
    cp .env.example .env || error "Failed to create .env file"
    info "Created .env file from example"

    # Ensure the hostname is set to iotpilot.local
    sed -i "s/HOST_NAME=.*/HOST_NAME=iotpilot.local/" .env
    info "Set hostname to iotpilot.local in .env file"

    echo "You may want to edit the .env file to customize your installation:"
    echo "  - Set your Tailscale auth key if you want to use Tailscale"
    echo "  - Adjust other settings as needed"
  else
    info ".env file already exists, updating hostname..."
    # Update hostname in existing .env
    sed -i "s/HOST_NAME=.*/HOST_NAME=iotpilot.local/" .env
    info "Updated hostname to iotpilot.local in existing .env file"
  fi
}

# Run installation
run_installation() {
  info "Starting IotPilot installation..."

  # Ensure correct permissions
  if [ "$SUDO_USER" ]; then
    # Run make commands as the regular user
    SUDO_CMD="sudo -u $SUDO_USER"
  else
    SUDO_CMD=""
  fi

  # Generate certificates
  info "Generating SSL certificates..."
  $SUDO_CMD make generate-certs || warn "Certificate generation failed, continuing anyway"

  # Install certificates to system trust store
  info "Installing certificates to system trust store..."
  make install-cert || warn "Certificate installation to system trust store failed, continuing anyway"

  # Setup hosts file
  info "Setting up hosts file..."
  make setup-hosts || warn "Hosts file setup failed, continuing anyway"

  # Modify Makefile for Raspberry Pi if needed
  if [ "$IS_RASPBERRY" = true ]; then
    # Check if docker-compose.raspberry.yml exists
    if [ -f "docker/docker-compose.raspberry.yml" ]; then
      info "Updating Makefile to use Raspberry Pi specific configuration..."
      # Backup the original Makefile
      cp Makefile Makefile.original
      # Modify the DOCKER_BINARY variable to use the Raspberry Pi specific compose file
      sed -i 's/DOCKER_BINARY := docker-compose -f docker\/docker-compose.yml/DOCKER_BINARY := docker-compose -f docker\/docker-compose.raspberry.yml/' Makefile
      info "Updated Makefile to use Raspberry Pi specific docker-compose file"
    else
      warn "Raspberry Pi specific docker-compose file not found, using standard configuration"
    fi
  fi

  # Build and start the application
  info "Building and starting IotPilot..."
  make build || error "Build failed"
  make start || error "Failed to start IotPilot"

  # Update Tailscale domain if configured
  if grep -q "TAILSCALE_AUTH_KEY=tskey" .env; then
    info "Setting up Tailscale..."
    make update-tailscale-domain || warn "Tailscale domain update failed, continuing anyway"
  fi

  # Set ownership of all files back to the user
  if [ "$SUDO_USER" ]; then
    chown -R "$SUDO_USER:$SUDO_USER" .
    info "Set ownership of all files to $SUDO_USER"
  fi
}

# Create systemd service for auto-start on boot
create_systemd_service() {
  info "Creating systemd service for auto-start on boot..."

  SERVICE_FILE="/etc/systemd/system/iotpilot.service"

  # Create the service file
  cat > "$SERVICE_FILE" << EOL
[Unit]
Description=IotPilot IoT Device Management
After=docker.service avahi-daemon.service
Requires=docker.service
Wants=avahi-daemon.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/iotpilot
ExecStart=/usr/bin/make start
ExecStop=/usr/bin/make stop
TimeoutStartSec=0

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
  # Always use iotpilot.local as the hostname
  HOSTNAME="iotpilot.local"

  echo
  echo -e "${GREEN}=============================================${NC}"
  echo -e "${GREEN}         IotPilot Installation Complete      ${NC}"
  echo -e "${GREEN}=============================================${NC}"
  echo
  echo "Your IotPilot instance is now running!"
  echo
  echo "Access your installation at:"
  echo "  - Local HTTP:  http://$HOSTNAME:4080"
  echo "  - Local HTTPS: https://$HOSTNAME:4443"
  echo
  echo "API documentation is available at:"
  echo "  - http://$HOSTNAME:4080/api-docs"
  echo
  echo "Traefik dashboard is available at:"
  echo "  - http://$HOSTNAME:8080"
  echo
  echo "The installation directory is: /opt/iotpilot"
  echo
  echo "mDNS has been configured, so any device on your local network"
  echo "should be able to access your server using iotpilot.local"
  echo
  echo "Useful commands (run from /opt/iotpilot directory):"
  echo "  - make stop    : Stop all services"
  echo "  - make start   : Start all services"
  echo "  - make restart : Restart all services"
  echo "  - make shell   : Access the IotPilot shell"
  echo "  - make logs-nodejs : View IotPilot application logs"
  echo

  # If we're running as root but with sudo, remind about docker permissions
  if [ "$SUDO_USER" ]; then
    echo "NOTICE: You may need to log out and back in for docker permissions to take effect."
    echo "        For now, Docker commands have been set up to work in this session."
    echo
  fi

  echo "TIP: For clients that don't support mDNS natively (older Windows versions),"
  echo "     you may need to install additional software like Bonjour Print Services."
}

# Main installation process
main() {
  echo
  echo -e "${GREEN}=============================================${NC}"
  echo -e "${GREEN}        IotPilot Autoinstaller Script        ${NC}"
  echo -e "${GREEN}=============================================${NC}"
  echo

  echo "This script will install IotPilot and its dependencies."
  echo "The installation process might take several minutes."
  echo

  # Non-interactive mode: proceed without confirmation
  info "Starting installation process..."
  install_dependencies
  setup_mdns  # Added the mDNS setup step
  clone_repository
  setup_environment
  run_installation
  create_systemd_service
  show_information
}

# Run the main installation function
main

exit 0