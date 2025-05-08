#!/bin/sh

set -e

# Check for TUN device
if [ ! -e /dev/net/tun ]; then
    echo "ERROR: TUN/TAP device is not available. Cannot run Tailscale."
    echo "Try adding --device=/dev/net/tun to your docker run command."
    exit 1
fi

# Create /tmp/tailscaled.sock (parent) directory in case it doesn't exist
mkdir -p /var/run/tailscale
chmod 1777 /var/run/tailscale

echo "Starting Tailscale daemon on Raspberry Pi..."

# Always use USERSPACE mode on Raspberry Pi for better compatibility
echo "Running in USERSPACE mode (optimized for Raspberry Pi)"
TAILSCALED_ARGS="--tun=userspace-networking"

# Reduce memory usage for Raspberry Pi
export TS_LOGS_DIR=/dev/null

# Start tailscaled with reduced logging and resources for ARM devices
tailscaled --state=$TS_STATE_DIR \
          --socket=/var/run/tailscale/tailscaled.sock \
          --verbose=0 \
          $TAILSCALED_ARGS &
TAILSCALED_PID=$!

# Give tailscaled more time to start on lower-powered devices
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