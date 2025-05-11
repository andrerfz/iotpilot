#!/bin/bash
# Script to update Tailscale domain from the container

# Check if TAILSCALE_DOMAIN is already set in .env
if grep -q "TAILSCALE_DOMAIN=.\+" .env; then
  echo "TAILSCALE_DOMAIN already set in .env file."
  exit 0
fi

# Check if container is running
if ! docker ps | grep -q "iotpilot-tailscale"; then
  echo "Tailscale container not running. Start containers first."
  exit 1
fi

# Get Tailscale domain from container
echo "Getting Tailscale domain from container..."
CONTAINER_TAILSCALE_INFO=$(docker exec iotpilot-tailscale tailscale status --json)

if [ $? -ne 0 ]; then
  echo "Error retrieving Tailscale information from container."
  exit 1
fi

# Extract the MagicDNSSuffix
TAILSCALE_DOMAIN=$(echo "$CONTAINER_TAILSCALE_INFO" | jq -r '.MagicDNSSuffix')

if [ -z "$TAILSCALE_DOMAIN" ] || [ "$TAILSCALE_DOMAIN" = "null" ]; then
  echo "No Tailscale domain found in container. Tailscale may not be properly configured."
  exit 1
fi

# Get hostname from container
CONTAINER_HOSTNAME=$(docker exec iotpilot-tailscale hostname)
if [ -z "$CONTAINER_HOSTNAME" ]; then
  # Fallback to the container name if hostname command fails
  CONTAINER_HOSTNAME="iotpilot"
fi

# Create full domain
FULL_DOMAIN="${CONTAINER_HOSTNAME}.${TAILSCALE_DOMAIN}"

# Update .env file
if grep -q "TAILSCALE_DOMAIN=" .env; then
  # Replace existing entry
  sed -i.bak "s/TAILSCALE_DOMAIN=.*/TAILSCALE_DOMAIN=${FULL_DOMAIN}/" .env
  echo "Updated TAILSCALE_DOMAIN in .env to ${FULL_DOMAIN}"
else
  # Add new entry
  echo "TAILSCALE_DOMAIN=${FULL_DOMAIN}" >> .env
  echo "Added TAILSCALE_DOMAIN=${FULL_DOMAIN} to .env file"
fi

# Check if restart is needed
echo "Tailscale domain set to ${FULL_DOMAIN}"
echo "A restart is recommended to apply the new domain configuration."
echo "Run 'make restart' to restart the services."

# Optionally, automatically restart
read -p "Do you want to restart services now? (y/N): " RESTART
if [[ "$RESTART" =~ ^[Yy]$ ]]; then
  echo "Restarting services..."
  make restart
fi