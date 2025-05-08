#!/bin/bash

set -e

# Check for TUN device
if [ ! -e /dev/net/tun ]; then
    echo "ERROR: TUN/TAP device is not available. Cannot run Tailscale."
    echo "Try adding --device=/dev/net/tun to your docker run command."
    exit 1
fi

# Create directory if it doesn't exist
mkdir -p /var/run/tailscale
chmod 1777 /var/run/tailscale

echo "Starting Tailscale daemon (optimized for Raspberry Pi)..."

# Use userspace networking for better compatibility
echo "Running in USERSPACE mode"
TAILSCALED_ARGS="--tun=userspace-networking"

# Add optimizations for Raspberry Pi
export TS_LOGS_DIR=/dev/null
export TS_LOG_TARGET=syslog

# Start tailscaled
tailscaled \
  --state=$TS_STATE_DIR \
  --socket=/var/run/tailscale/tailscaled.sock \
  --port=41641 \
  --verbose=0 \
  $TAILSCALED_ARGS &
TAILSCALED_PID=$!

# Give tailscaled some time to start
sleep 5

# Try to log in with the auth key if provided
if [ -n "$TS_AUTHKEY" ]; then
    echo "Starting Tailscale with provided auth key..."
    tailscale up --authkey="$TS_AUTHKEY" $TS_EXTRA_ARGS
else
    echo "No auth key provided. Please run 'docker exec -it [container] tailscale up' to authenticate."
fi

# Keep running until tailscaled exits
echo "Tailscale started successfully! Monitoring..."
wait $TAILSCALED_PID