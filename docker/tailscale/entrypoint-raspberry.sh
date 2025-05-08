#!/bin/sh

set -e

# Check for TUN device
if [ ! -e /dev/net/tun ]; then
    echo "ERROR: TUN/TAP device is not available. Cannot run Tailscale."
    echo "Try adding --device=/dev/net/tun to your docker run command."
    exit 1
fi

# Create /tmp/tailscaled.sock directory in case it doesn't exist
mkdir -p /var/run/tailscale
chmod 1777 /var/run/tailscale

# Set up low memory optimizations for ARMv6
echo "Starting Tailscale daemon optimized for ARMv6..."

# Always use userspace mode for ARMv6 devices
echo "Running in USERSPACE mode (optimized for ARMv6)"
TAILSCALED_ARGS="--tun=userspace-networking"

# Reduce memory usage for low-powered devices
export TS_LOGS_DIR=/dev/null
export TS_LOG_TARGET=syslog
export TS_USERSPACE_ROUTER=true

# Start tailscaled with minimal memory consumption
tailscaled \
  --state=$TS_STATE_DIR \
  --socket=/var/run/tailscale/tailscaled.sock \
  --port=41641 \
  --verbose=0 \
  $TAILSCALED_ARGS &
TAILSCALED_PID=$!

# Give tailscaled extra time to start on the resource-constrained device
sleep 8

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