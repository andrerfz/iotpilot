#!/bin/sh
# This is the entrypoint script that will be executed when the container starts

# Create data directory with proper permissions
mkdir -p /app/data
chmod 777 /app/data

# Execute the command passed to docker run
exec "$@"