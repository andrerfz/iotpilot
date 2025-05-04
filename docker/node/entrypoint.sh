#!/bin/bash
set -e

# Create data directory if it doesn't exist
mkdir -p /app/data

# Set permissions only if needed (check first to avoid doing it every time)
if [ ! -w "/app/data" ]; then
  echo "Setting permissions for data directory..."
  chmod 777 /app/data
fi

# Run the command
exec "$@"