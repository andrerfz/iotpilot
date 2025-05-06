#!/bin/bash
# Get Tailscale domain and add to .env file
TAILSCALE_DOMAIN=$(tailscale status --json | jq -r '.MagicDNSSuffix')
if [ -n "$TAILSCALE_DOMAIN" ]; then
  # Get hostname
  HOSTNAME=$(hostname)
  # Create full domain
  FULL_DOMAIN="${HOSTNAME}.${TAILSCALE_DOMAIN}"
  # Update .env file
  if grep -q "TAILSCALE_DOMAIN" .env; then
    sed -i "s/TAILSCALE_DOMAIN=.*/TAILSCALE_DOMAIN=${FULL_DOMAIN}/" .env
  else
    echo "TAILSCALE_DOMAIN=${FULL_DOMAIN}" >> .env
  fi
  echo "Tailscale domain set to ${FULL_DOMAIN}"
else
  echo "Unable to detect Tailscale domain. Make sure Tailscale is running."
fi