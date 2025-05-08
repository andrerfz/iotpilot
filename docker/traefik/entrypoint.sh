#!/bin/sh

set -e

# Create directories if they don't exist
mkdir -p /etc/traefik/acme
chmod 600 /etc/traefik/acme

# Check if we need to generate certificates
if [ ! -f /etc/traefik/config/certs/local-cert.pem ] && [ ! -f /etc/traefik/config/certs/local-key.pem ]; then
    echo "SSL certificates not found in expected location. Make sure to mount the proper volume."
fi

echo "Starting Traefik..."
exec "$@"