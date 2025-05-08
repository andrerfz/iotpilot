#!/bin/sh

set -e

# Create directories if they don't exist
mkdir -p /etc/traefik/acme
chmod 600 /etc/traefik/acme

# Optimize for Raspberry Pi: Set lower resource limits
export GOGC=20  # More aggressive garbage collection
export GOMAXPROCS=2  # Limit CPU usage

# Check if we need to generate certificates
if [ ! -f /etc/traefik/config/certs/local-cert.pem ] && [ ! -f /etc/traefik/config/certs/local-key.pem ]; then
    echo "SSL certificates not found in expected location. Make sure to mount the proper volume."
fi

echo "Starting Traefik on Raspberry Pi with optimized settings..."
exec "$@"