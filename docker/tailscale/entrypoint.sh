#!/bin/sh
# docker/tailscale/entrypoint.sh

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

echo "Starting Tailscale daemon..."

# Use USERSPACE mode for better compatibility in Docker
if [ "$TS_USERSPACE" = "true" ]; then
    echo "Running in USERSPACE mode"
    TAILSCALED_ARGS="--tun=userspace-networking"
else
    echo "Running in normal mode"
    TAILSCALED_ARGS=""
fi

# Start tailscaled
tailscaled --state=$TS_STATE_DIR \
          --socket=/var/run/tailscale/tailscaled.sock \
          $TAILSCALED_ARGS &
TAILSCALED_PID=$!

# Give tailscaled some time to start
sleep 2

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