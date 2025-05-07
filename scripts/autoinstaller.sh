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

# Fix docker-compose.yml file for compatibility
fix_docker_compose_file() {
  info "Fixing docker-compose.yml for compatibility..."

  local compose_file="docker/docker-compose.yml"

  if [ ! -f "$compose_file" ]; then
    error "docker-compose.yml not found at expected location: $compose_file"
  fi

  # Create a backup of the original file
  cp "$compose_file" "${compose_file}.original"

  # Check Docker Compose version
  local compose_version
  if command -v docker-compose &>/dev/null; then
    compose_version=$(docker-compose --version | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    info "Detected Docker Compose version: $compose_version"
  else
    compose_version="unknown"
    warn "Docker Compose not found or version could not be determined"
  fi

  # Fix the 'name:' directive
  info "Removing 'name:' directive from docker-compose.yml..."
  if grep -q "^name:" "$compose_file"; then
    sed -i '/^name:/d' "$compose_file"
  fi

  # Add version if it doesn't exist
  if ! grep -q "^version:" "$compose_file"; then
    # Add version: '3' at the beginning of the file
    sed -i '1s/^/version: "3"\n\n/' "$compose_file"
    info "Added version: '3' to docker-compose.yml"
  fi

  # Ensure services are properly defined
  if ! grep -q "^services:" "$compose_file"; then
    # First, count how many spaces are commonly used for indentation
    local indent=$(grep -P '^\s+\w+:' "$compose_file" | head -1 | sed 's/[^ ].*//')
    if [ -z "$indent" ]; then
      indent="  " # Default to 2 spaces if we can't determine
    fi

    # Wrap all current service definitions in a services: section
    # 1. Create a temp file with just 'services:'
    echo "services:" > temp_compose.yml

    # 2. Add the rest of the file with proper indentation
    while IFS= read -r line; do
      if [[ "$line" =~ ^[a-zA-Z] && ! "$line" =~ ^version: ]]; then
        # This is a top-level directive that's not 'version:'
        echo "$indent$line" >> temp_compose.yml
      else
        # Add more indentation to all already indented lines
        if [[ "$line" =~ ^[[:space:]] ]]; then
          echo "$indent$line" >> temp_compose.yml
        else
          # Pass through other lines unchanged (like version:, blank lines)
          echo "$line" >> temp_compose.yml
        fi
      fi
    done < <(grep -v "^version:" "$compose_file")

    # 3. Replace the original file
    mv temp_compose.yml "$compose_file"
    info "Wrapped service definitions in 'services:' section"
  fi

  # Validate the modified file
  if ! docker-compose -f "$compose_file" config --quiet 2>/dev/null; then
    warn "Modified docker-compose.yml may still have issues. Manual review recommended."
    info "Original file saved as ${compose_file}.original"
  else
    info "docker-compose.yml successfully modified for compatibility"
  fi
}

# Fix Makefile Docker Compose command
fix_makefile() {
  info "Fixing Makefile Docker Compose command if needed..."

  local makefile="Makefile"

  if [ ! -f "$makefile" ]; then
    warn "Makefile not found at expected location: $makefile"
    return
  fi

  # Create a backup of the original file
  cp "$makefile" "${makefile}.original"

  # Check if it uses docker-compose command
  if grep -q "docker-compose " "$makefile"; then
    info "Makefile uses 'docker-compose' command. No changes needed."
  else
    # Check if it's using the new docker compose command format
    if grep -q "docker compose " "$makefile"; then
      # Change to the old format for compatibility
      sed -i 's/docker compose /docker-compose /g' "$makefile"
      info "Updated Makefile to use 'docker-compose' command for compatibility"
    fi
  fi
}

# Run installation
run_installation() {
  info "Starting IotPilot installation..."

  # Fix docker-compose.yml file
  fix_docker_compose_file

  # Fix Makefile if needed
  fix_makefile

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

  # Build and start the application with root permissions to ensure it works
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
    echo "        For now, Docker commands have been set up to work in this session."
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