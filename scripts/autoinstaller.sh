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
else
  MODEL=$(tr -d '\0' < /proc/device-tree/model)
  info "Detected: $MODEL"
  if [[ "$MODEL" != *"Raspberry Pi"* ]]; then
    warn "This doesn't appear to be a Raspberry Pi. Installation might not work correctly."
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
    jq || error "Failed to install required packages"

  # Enable and start Docker service
  info "Enabling and starting Docker service..."
  systemctl enable docker
  systemctl start docker

  # Add current user to docker group to avoid using sudo with docker
  if [ "$SUDO_USER" ]; then
    usermod -aG docker $SUDO_USER
    info "Added user $SUDO_USER to the docker group"
  else
    warn "Could not determine the sudo user. You may need to add your user to the docker group manually."
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
    chown -R $SUDO_USER:$SUDO_USER "$repo_dir"
  fi

  cd "$repo_dir" || error "Failed to enter repository directory"
}

# Setup environment
setup_environment() {
  info "Setting up environment..."

  # Create .env file from example if it doesn't exist
  if [ ! -f .env ]; then
    cp .env.example .env || error "Failed to create .env file"
    info "Created .env file from example"

    # Generate a random hostname if needed
    RANDOM_SUFFIX=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)
    HOSTNAME="iotpilot-$RANDOM_SUFFIX.local"

    # Update the hostname in .env
    sed -i "s/HOST_NAME=.*/HOST_NAME=$HOSTNAME/" .env
    info "Set hostname to $HOSTNAME"

    echo "You may want to edit the .env file to customize your installation:"
    echo "  - Set your Tailscale auth key if you want to use Tailscale"
    echo "  - Adjust other settings as needed"
  else
    info ".env file already exists, keeping existing configuration"
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

  # Build and start the application
  info "Building and starting IotPilot..."
  $SUDO_CMD make build || error "Build failed"
  $SUDO_CMD make start || error "Failed to start IotPilot"

  # Update Tailscale domain if configured
  if grep -q "TAILSCALE_AUTH_KEY=tskey" .env; then
    info "Setting up Tailscale..."
    $SUDO_CMD make update-tailscale-domain || warn "Tailscale domain update failed, continuing anyway"
  fi
}

# Create systemd service for auto-start on boot
create_systemd_service() {
  info "Creating systemd service for auto-start on boot..."

  SERVICE_FILE="/etc/systemd/system/iotpilot.service"

  # Create the service file
  cat > $SERVICE_FILE << EOL
[Unit]
Description=IotPilot IoT Device Management
After=docker.service
Requires=docker.service

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
  # Get hostname from .env file
  HOSTNAME=$(grep HOST_NAME .env | cut -d '=' -f2 | tr -d '"' | tr -d "'" || echo "iotpilot.local")

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
    echo
  fi
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
  clone_repository
  setup_environment
  run_installation
  create_systemd_service
  show_information
}

# Run the main installation function
main

exit 0