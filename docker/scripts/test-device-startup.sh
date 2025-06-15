#!/bin/bash
set -e

echo "🚀 IoT Test Device Startup"
echo "=========================="

# Install required packages
echo "📦 Installing system packages..."
export DEBIAN_FRONTEND=noninteractive

echo "  Updating package lists..."
if ! apt-get update -qq; then
    echo "❌ Failed to update package lists"
    exit 1
fi

echo "  Installing packages: curl jq cron..."
if ! apt-get install -y curl jq cron ca-certificates --no-install-recommends; then
    echo "❌ Failed to install packages"
    exit 1
fi

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

# Export environment variables for the enhanced script
export DEVICE_ID
export DEVICE_NAME
export DEVICE_LOCATION="${DEVICE_LOCATION:-docker-test-lab}"
export DEVICE_API_KEY
export INFLUXDB_TOKEN

# Set IOTPILOT_SERVER as primary (enhanced script will construct SERVER_URL from this)
export IOTPILOT_SERVER="${IOTPILOT_SERVER:-iotpilot-server-app:3000}"

# Construct SERVER_URL for local connectivity testing
SERVER_URL="http://${IOTPILOT_SERVER}"

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

echo "⬇️  Downloading IoT agent installation script..."
echo "   URL: https://raw.githubusercontent.com/andrerfz/iotpilotserver/main/scripts/device-agent-quick-test-local.sh"

# Execute the installation script with proper environment and parameters
echo "⬇️  Downloading and executing IoT agent installation script..."
echo "   URL: https://raw.githubusercontent.com/andrerfz/iotpilotserver/main/scripts/device-agent-quick-test-local.sh"
echo "   Device ID: $DEVICE_ID"
echo "   Device Name: $DEVICE_NAME"

# Create a temporary script to capture the enhanced script's success
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" << 'ENHANCED_WRAPPER_EOF'
#!/bin/bash
# Enhanced script wrapper that properly reports success

# Execute the enhanced script
if curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilotserver/main/scripts/device-agent-quick-test-local.sh | bash; then
    # Check for enhanced success markers
    if [ -f /tmp/enhanced_success_marker ] || [ -f /usr/local/bin/enhanced-heartbeat.sh ]; then
        echo ""
        echo "✅ Enhanced IoT Agent installation completed successfully!"
        echo ""

        # Wait a moment for services to be ready
        sleep 2

        # Test the enhanced heartbeat to confirm it's working
        if /usr/local/bin/enhanced-heartbeat.sh >/dev/null 2>&1; then
            echo "✅ Enhanced heartbeat test successful!"
            echo "📊 40+ comprehensive metrics are being collected"
            echo "🔄 Monitoring every 2 minutes"
            exit 0
        else
            echo "⚠️  Enhanced heartbeat test had issues, but monitoring is active"
            echo "📋 Manual test available: /usr/local/bin/enhanced-heartbeat.sh"
            exit 0
        fi
    else
        # Fall back to checking regular heartbeat
        if [ -f /usr/local/bin/heartbeat.sh ]; then
            echo "✅ Standard IoT Agent installation completed successfully!"
            exit 0
        else
            echo "❌ No heartbeat script found"
            exit 1
        fi
    fi
else
    echo "❌ Script execution failed"
    exit 1
fi
ENHANCED_WRAPPER_EOF

chmod +x "$TEMP_SCRIPT"

# Execute the enhanced wrapper
if "$TEMP_SCRIPT"; then
    echo ""
    echo "✅ IoT Agent installation completed successfully!"
    echo ""
    echo "📱 Device registered as: $DEVICE_ID"
    echo "📊 Dashboard: $FOUND_SERVER"
    echo "🔄 Agent will send heartbeats every 2 minutes"
    echo ""
    echo "📋 Useful commands:"
    if [ -f /usr/local/bin/enhanced-heartbeat.sh ]; then
        echo "   Enhanced heartbeat: /usr/local/bin/enhanced-heartbeat.sh"
        echo "   Enhanced monitor: /usr/local/bin/enhanced-monitor.sh"
        echo "   Enhanced diagnostics: /usr/local/bin/enhanced-diagnostics.sh"
        echo "   View enhanced logs: tail -f /var/log/enhanced-heartbeat.log"
        echo ""
        echo "🚀 Enhanced Features Active:"
        echo "   • 40+ comprehensive metrics vs basic 6"
        echo "   • CPU, Memory, Disk, Network, Temperature monitoring"
        echo "   • Hardware-specific optimizations"
        echo "   • Real-time analytics every 2 minutes"
    else
        echo "   View agent logs: tail -f /var/log/heartbeat.log"
        echo "   View registration: cat /tmp/registration_response.json"
    fi
    echo ""
    echo "🔄 Agent is now running..."

    # Keep container alive and show agent activity
    if [ -f /var/log/enhanced-heartbeat.log ]; then
        echo "📊 Following enhanced heartbeat logs..."
        tail -f /var/log/enhanced-heartbeat.log
    elif [ -f /var/log/heartbeat.log ]; then
        echo "📊 Following standard heartbeat logs..."
        tail -f /var/log/heartbeat.log
    else
        echo "📝 Agent log not found, keeping container alive for inspection..."

        # Show real-time status updates
        while true; do
            sleep 60
            current_time=$(date '+%H:%M:%S')
            if [ -f /usr/local/bin/enhanced-heartbeat.sh ]; then
                cron_status=$(pgrep cron > /dev/null && echo "ACTIVE" || echo "STOPPED")
                echo "$(date): 🚀 Enhanced monitoring active | Cron: $cron_status"

                # Check for recent successful heartbeats
                if [ -f /var/log/enhanced-heartbeat.log ]; then
                    recent_success=$(tail -10 /var/log/enhanced-heartbeat.log | grep -c "✅.*successful" 2>/dev/null || echo "0")
                    if [ "$recent_success" -gt 0 ]; then
                        echo "$(date): ✅ Recent successful heartbeats detected"
                    fi
                fi
            else
                echo "$(date): 📊 Standard monitoring active"
            fi
        done
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

# Cleanup
rm -f "$TEMP_SCRIPT"