#!/bin/bash

# IotPilot Raspberry Pi Zero 2W Installer
# This script installs IotPilot directly on a Raspberry Pi Zero 2W running Debian Bookworm
# Usage:
#   Basic: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero.sh | sudo bash
#   With Tailscale key: curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero.sh | sudo TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash



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