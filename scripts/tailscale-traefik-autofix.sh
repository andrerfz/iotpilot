#!/bin/bash

# Tailscale-Traefik Auto Fix Script
# This script automatically keeps the Traefik configuration in sync with Tailscale domains
# Run as a systemd timer every 5 minutes

# Log file
LOG_FILE="/var/log/tailscale-traefik-autofix.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Get the current Tailscale DNS name (removing trailing period if present)
CURRENT_TAILSCALE_DOMAIN=$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')

# Check if we got a valid domain name
if [ -z "$CURRENT_TAILSCALE_DOMAIN" ] || [ "$CURRENT_TAILSCALE_DOMAIN" = "null" ]; then
    log "Error: Could not get Tailscale domain. Tailscale may not be running or configured properly."
    exit 1
fi

log "Current Tailscale domain: $CURRENT_TAILSCALE_DOMAIN"

# Paths to configuration files
ENV_FILE="/opt/iotpilot/.env"
TRAEFIK_CONFIG="/etc/traefik/config/iotpilot.yml"
TRAEFIK_MAIN_CONFIG="/etc/traefik/traefik.yml"

# Check if changes are needed
NEEDS_UPDATE=0

# 1. Check .env file
if [ -f "$ENV_FILE" ]; then
    CURRENT_ENV_DOMAIN=$(grep "TAILSCALE_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'")

    if [ "$CURRENT_ENV_DOMAIN" != "$CURRENT_TAILSCALE_DOMAIN" ]; then
        log "Updating Tailscale domain in .env file from '$CURRENT_ENV_DOMAIN' to '$CURRENT_TAILSCALE_DOMAIN'"
        # Remove existing TAILSCALE_DOMAIN line
        sed -i '/TAILSCALE_DOMAIN=/d' "$ENV_FILE"
        # Add new TAILSCALE_DOMAIN line
        echo "TAILSCALE_DOMAIN=$CURRENT_TAILSCALE_DOMAIN" >> "$ENV_FILE"
        NEEDS_UPDATE=1
    else
        log ".env file already has correct domain: $CURRENT_ENV_DOMAIN"
    fi
else
    log "Warning: .env file not found at $ENV_FILE"
fi

# 2. Check and fix Traefik router configuration
if [ -f "$TRAEFIK_CONFIG" ]; then
    # Check if the current domain exists in the tailscale router specifically
    if ! grep -A3 "iotpilot-tailscale:" "$TRAEFIK_CONFIG" | grep -q "Host(\`$CURRENT_TAILSCALE_DOMAIN\`)" 2>/dev/null; then
        log "Tailscale domain not found in iotpilot-tailscale router, updating configuration..."

        # Create a new corrected configuration file
        cat > "$TRAEFIK_CONFIG.new" << EOF
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

    iotpilot-tailscale:
      rule: "Host(\`$CURRENT_TAILSCALE_DOMAIN\`)"
      entrypoints:
        - websecure
      service: iotpilot
      tls: true

  services:
    iotpilot:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:4000"
EOF

        # Replace the configuration file
        mv "$TRAEFIK_CONFIG.new" "$TRAEFIK_CONFIG"
        log "Traefik configuration updated with correct local and Tailscale domains"
        NEEDS_UPDATE=1
    else
        log "Traefik configuration already has correct domain rules"
    fi
else
    log "Error: Traefik configuration file not found at $TRAEFIK_CONFIG"
fi

# 3. Check main Traefik configuration for TLS domain
if [ -f "$TRAEFIK_MAIN_CONFIG" ]; then
    # Check if our Tailscale domain is in the TLS configuration
    if ! grep -q "$CURRENT_TAILSCALE_DOMAIN" "$TRAEFIK_MAIN_CONFIG"; then
        log "Adding Tailscale domain to main Traefik TLS configuration"

        # Use a more precise approach to add the domain
        # First, check if there's already a placeholder domain that we need to replace
        if grep -q "iotpilot\.tail.*\.ts\.net" "$TRAEFIK_MAIN_CONFIG"; then
            # Replace any existing iotpilot.tail*.ts.net domain with the current one
            sed -i "s/iotpilot\.tail[^\"]*\.ts\.net/$CURRENT_TAILSCALE_DOMAIN/g" "$TRAEFIK_MAIN_CONFIG"
            log "Replaced existing Tailscale domain in main configuration"
            NEEDS_UPDATE=1
        else
            # Add the domain to the TLS section if it's not there
            # This is more complex and requires careful YAML manipulation
            # We'll use a simpler approach: replace the entire websecure section

            # Create a backup first
            cp "$TRAEFIK_MAIN_CONFIG" "$TRAEFIK_MAIN_CONFIG.backup"

            # Use awk to rebuild the configuration with the correct domains
            awk -v tailscale_domain="$CURRENT_TAILSCALE_DOMAIN" '
            BEGIN { in_websecure = 0; in_tls = 0; in_domains = 0; websecure_done = 0 }

            /^[[:space:]]*websecure:/ {
                print $0
                in_websecure = 1
                next
            }

            in_websecure && /^[[:space:]]*address:/ {
                print $0
                next
            }

            in_websecure && /^[[:space:]]*http:/ {
                print $0
                in_tls = 1
                next
            }

            in_websecure && in_tls && /^[[:space:]]*tls:/ {
                print $0
                print "        domains:"
                print "          - main: \"iotpilot.local\""
                print "            sans:"
                print "              - \"*.iotpilot.local\""
                print "          - main: \"" tailscale_domain "\""
                print "            sans:"
                print "              - \"*." tailscale_domain "\""
                in_domains = 1
                next
            }

            in_domains && /^[[:space:]]*domains:/ {
                # Skip the original domains section
                next
            }

            in_domains && /^[[:space:]]*-[[:space:]]*main:/ {
                # Skip domain entries
                next
            }

            in_domains && /^[[:space:]]*sans:/ {
                # Skip sans entries
                next
            }

            in_domains && /^[[:space:]]*-[[:space:]]*".*"/ {
                # Skip sans domain entries
                next
            }

            /^[^[:space:]]/ && in_websecure {
                # End of websecure section
                in_websecure = 0
                in_tls = 0
                in_domains = 0
                websecure_done = 1
            }

            # Print all other lines
            !in_domains || (in_domains && !/^[[:space:]]*domains:/ && !/^[[:space:]]*-[[:space:]]*main:/ && !/^[[:space:]]*sans:/ && !/^[[:space:]]*-[[:space:]]*".*"/) {
                print $0
            }
            ' "$TRAEFIK_MAIN_CONFIG" > "$TRAEFIK_MAIN_CONFIG.tmp"

            mv "$TRAEFIK_MAIN_CONFIG.tmp" "$TRAEFIK_MAIN_CONFIG"
            log "Updated main Traefik configuration with Tailscale domain"
            NEEDS_UPDATE=1
        fi
    else
        log "Main Traefik configuration already has Tailscale domain"
    fi
else
    log "Error: Main Traefik configuration file not found at $TRAEFIK_MAIN_CONFIG"
fi

# If any changes were made, restart Traefik
if [ "$NEEDS_UPDATE" -eq 1 ]; then
    log "Configuration updated, restarting Traefik service..."
    systemctl restart traefik
    if [ $? -eq 0 ]; then
        log "Traefik service restarted successfully"
    else
        log "Error: Failed to restart Traefik service"
    fi
else
    log "No changes needed, all configurations are up-to-date"
fi

log "Auto-fix process completed"
exit 0