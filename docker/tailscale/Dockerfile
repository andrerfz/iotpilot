# docker/traefik/Dockerfile
FROM traefik:v2.10

# Install some utilities for troubleshooting
RUN apk update && apk add --no-cache \
    curl \
    ca-certificates \
    openssl

# Create directory for dynamic configuration
RUN mkdir -p /etc/traefik/config

# Create a custom entrypoint script
COPY docker/traefik/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["traefik"]