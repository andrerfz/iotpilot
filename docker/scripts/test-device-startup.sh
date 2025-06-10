#!/bin/bash
set -e

echo "🚀 IoT Test Device Startup"
echo "=========================="

# Install required packages
echo "📦 Installing system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y curl jq sudo systemd cron >/dev/null 2>&1
echo "✅ System packages installed"

# Use fixed device ID from environment or generate fallback
if [ -z "$DEVICE_ID" ]; then
    # Generate device ID if not provided (fallback)
    if [ -f /.dockerenv ]; then
        # In Docker container - use container hostname
        DEVICE_ID="test-device-$(hostname)"
    else
        # Not in Docker
        DEVICE_ID="test-device-$(hostname)"
    fi
fi

# Use environment variables or defaults
DEVICE_NAME="${DEVICE_NAME:-$DEVICE_ID}"

# Display configuration
echo ""
echo "📋 Configuration:"
echo "  DEVICE_ID: ${DEVICE_ID}"
echo "  DEVICE_NAME: ${DEVICE_NAME}"
echo "  IOTPILOT_SERVER: ${IOTPILOT_SERVER}"
echo "  DEVICE_API_KEY: ${DEVICE_API_KEY:0:8}..."
echo "  DEVICE_LOCATION: ${DEVICE_LOCATION}"
echo "  INFLUXDB_TOKEN: ${INFLUXDB_TOKEN:0:8}..."
echo ""

# Test server connectivity
echo "🔍 Testing server connectivity..."
SERVER_URL="http://iotpilot-server-app:3000"

echo -n "  Testing ${SERVER_URL}... "
if curl -f --connect-timeout 5 --max-time 10 "${SERVER_URL}/api/health" >/dev/null 2>&1; then
    echo "✅ OK"
    FOUND_SERVER="$SERVER_URL"
else
    echo "❌ FAIL"
    echo "❌ No server accessible"
    tail -f /dev/null
    exit 1
fi

echo ""
echo "🎯 Using server: $FOUND_SERVER"
echo "📱 Device will register as: $DEVICE_ID"

# Export environment variables for the GitHub script
export IOTPILOT_SERVER="iotpilot-server-app:3000"  # Internal HTTP
export DEVICE_ID  # Pass the fixed device ID
export DEVICE_NAME

echo "⬇️  Downloading IoT agent installation script..."
echo "   URL: https://raw.githubusercontent.com/andrerfz/iotpilotserver/main/scripts/device-agent-quick-test-local.sh"

# Execute the installation script with proper environment
if curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilotserver/main/scripts/device-agent-quick-test-local.sh | bash; then
    echo ""
    echo "✅ IoT Agent installation completed successfully!"
    echo ""
    echo "📱 Device registered as: $DEVICE_ID"
    echo "📊 Dashboard: $FOUND_SERVER"
    echo "🔄 Agent will send heartbeats every 2 minutes"
    echo ""
    echo "📋 Useful commands:"
    echo "   View agent logs: tail -f /var/log/heartbeat.log"
    echo "   View registration: cat /tmp/registration_response.json"
    echo ""
    echo "🔄 Agent is now running..."

    # Keep container alive and show agent activity
    if [ -f /var/log/heartbeat.log ]; then
        tail -f /var/log/heartbeat.log
    else
        echo "📝 Agent log not found, keeping container alive for inspection..."
        tail -f /dev/null
    fi
else
    echo ""
    echo "❌ IoT Agent installation failed"
    echo "💡 Server was accessible but installation failed"
    echo ""
    echo "🔍 Debug information:"
    echo "   Device ID: $DEVICE_ID"
    echo "   Server URL: $FOUND_SERVER"
    echo "   API Key: ${DEVICE_API_KEY:0:8}..."
    echo "   Location: $DEVICE_LOCATION"
    echo ""
    echo "🛠️  Container available for debugging:"
    echo "   docker exec -it iotpilot-test-device bash"
    echo ""

    # Keep container alive for debugging
    tail -f /dev/null
fi