#!/bin/bash

# IotPilot Device Agent Installer
# Adds monitoring and reporting to existing Pi installations
# Usage: curl -sSL https://raw.githubusercontent.com/yourusername/iotpilot/main/scripts/device-agent-install.sh | sudo TAILSCALE_HOSTNAME="custom-name" TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

header() {
    echo -e "${BLUE}[AGENT]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root (sudo)"
fi

# Configuration variables (can be set as environment variables)
IOTPILOT_SERVER="iotpilot.app"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
DEVICE_TOKEN="${DEVICE_TOKEN:-}"
DEVICE_LOCATION="${DEVICE_LOCATION:-unknown}"

# Auto-detect if this is being called from existing installation scripts
if [ -f "/opt/iotpilot/.env" ]; then
    info "Detected existing IotPilot installation, reading configuration..."
    source /opt/iotpilot/.env
fi

# Detect device type
detect_device_type() {
    header "Detecting device information..."

    if [ -f /proc/device-tree/model ]; then
        DEVICE_MODEL=$(tr -d '\0' < /proc/device-tree/model)
        info "Device: $DEVICE_MODEL"

        # Set device type based on model
        if [[ "$DEVICE_MODEL" == *"Pi Zero"* ]]; then
            DEVICE_TYPE="pi-zero"
        elif [[ "$DEVICE_MODEL" == *"Pi 3"* ]]; then
            DEVICE_TYPE="pi-3"
        elif [[ "$DEVICE_MODEL" == *"Pi 4"* ]]; then
            DEVICE_TYPE="pi-4"
        else
            DEVICE_TYPE="raspberry-pi"
        fi
    else
        DEVICE_TYPE="unknown"
        warn "Could not detect device model"
    fi

    # Get architecture
    ARCH=$(uname -m)
    info "Architecture: $ARCH"

    # Generate unique device ID
    DEVICE_ID=$(hostname)-$(cat /sys/class/net/eth0/address 2>/dev/null | tr -d ':' || echo "unknown")
    info "Device ID: $DEVICE_ID"

    export DEVICE_TYPE DEVICE_MODEL DEVICE_ID ARCH
}

# Install Tailscale for secure networking
install_tailscale() {
    header "Installing Tailscale for secure networking..."

    if command -v tailscale &> /dev/null; then
        info "Tailscale is already installed"
        return 0
    fi

    # Install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh
    TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-"iotpilot"}

    if [ -n "$TAILSCALE_AUTH_KEY" ]; then
        info "Connecting to Tailscale network..."
        tailscale up --authkey="$TAILSCALE_AUTH_KEY" \
                     --hostname="TAILSCALE_HOSTNAME" \
                     --advertise-tags=tag:iot-device \
                     --accept-routes
    else
        warn "No Tailscale auth key provided. Device will not be automatically connected."
        info "Run: sudo tailscale up --authkey=YOUR_KEY --hostname=TAILSCALE_HOSTNAME"
    fi
}

# Install and configure Telegraf for metrics collection
install_telegraf() {
    header "Installing Telegraf for metrics collection..."

    if command -v telegraf &> /dev/null; then
        info "Telegraf is already installed"
    else
        # Add InfluxData repository
        wget -qO- https://repos.influxdata.com/influxdb.key | apt-key add -
        echo "deb https://repos.influxdata.com/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/influxdb.list
        apt-get update
        apt-get install -y telegraf
    fi

    # Get Tailscale server address
    if command -v tailscale &> /dev/null && tailscale status &> /dev/null; then
        SERVER_ADDRESS=$(tailscale status --json | jq -r '.Peer[] | select(.HostName == "iotpilot-server") | .TailscaleIPs[0]')
        if [ -z "$SERVER_ADDRESS" ] || [ "$SERVER_ADDRESS" = "null" ]; then
            SERVER_ADDRESS="$IOTPILOT_SERVER"
        fi
    else
        SERVER_ADDRESS="$IOTPILOT_SERVER"
    fi

    info "Configuring Telegraf to send metrics to: $SERVER_ADDRESS"

    # Create Telegraf configuration
    cat > /etc/telegraf/telegraf.conf << EOF
# Global tags
[global_tags]
  device_id = "$DEVICE_ID"
  device_type = "$DEVICE_TYPE"
  device_model = "$DEVICE_MODEL"
  location = "$DEVICE_LOCATION"
  architecture = "$ARCH"

# Agent configuration
[agent]
  interval = "30s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "5s"
  flush_interval = "30s"
  flush_jitter = "5s"
  precision = ""
  hostname = "$DEVICE_ID"
  omit_hostname = false

# Output to InfluxDB
[[outputs.influxdb_v2]]
  urls = ["http://$SERVER_ADDRESS:8086"]
  token = "\$INFLUXDB_TOKEN"
  organization = "iotpilot"
  bucket = "devices"
  timeout = "10s"

# System metrics
[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]

[[inputs.diskio]]

[[inputs.kernel]]

[[inputs.mem]]

[[inputs.processes]]

[[inputs.swap]]

[[inputs.system]]

[[inputs.net]]
  interfaces = ["eth0", "wlan0"]

# Temperature sensors
[[inputs.file]]
  files = ["/sys/class/thermal/thermal_zone0/temp"]
  name_override = "cpu_temperature"
  data_format = "value"
  data_type = "integer"

[[inputs.file]]
  files = ["/sys/devices/virtual/thermal/thermal_zone0/temp"]
  name_override = "soc_temperature"
  data_format = "value"
  data_type = "integer"

# Service status
[[inputs.systemd_units]]
  unittype = "service"

# Docker metrics (if docker is installed)
[[inputs.docker]]
  endpoint = "unix:///var/run/docker.sock"
  gather_services = false
  container_names = []
  source_tag = false
  container_name_include = []
  container_name_exclude = []
  timeout = "5s"
  api_version = "1.24"

# Custom application metrics (if available)
[[inputs.http]]
  urls = ["http://localhost:4000/api/metrics"]
  timeout = "5s"
  data_format = "json"
  name_override = "iot_app"
  interval = "60s"
  [inputs.http.tags]
    source = "iotpilot_app"
EOF

    # Start and enable Telegraf
    systemctl enable telegraf
    systemctl restart telegraf

    info "Telegraf configured and started"
}

# Install and configure Promtail for log shipping
install_promtail() {
    header "Installing Promtail for log shipping..."

    if [ -f /usr/local/bin/promtail ]; then
        info "Promtail is already installed"
    else
        # Determine architecture for download
        PROMTAIL_VERSION="2.9.2"
        case "$ARCH" in
            "armv6l") PROMTAIL_ARCH="armv6" ;;
            "armv7l") PROMTAIL_ARCH="armv7" ;;
            "aarch64") PROMTAIL_ARCH="arm64" ;;
            *) PROMTAIL_ARCH="arm64" ;;
        esac

        info "Downloading Promtail for $PROMTAIL_ARCH..."
        wget "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-${PROMTAIL_ARCH}.zip" -O /tmp/promtail.zip
        unzip /tmp/promtail.zip -d /tmp/
        mv "/tmp/promtail-linux-${PROMTAIL_ARCH}" /usr/local/bin/promtail
        chmod +x /usr/local/bin/promtail
        rm /tmp/promtail.zip
    fi

    # Get server address
    if command -v tailscale &> /dev/null && tailscale status &> /dev/null; then
        SERVER_ADDRESS=$(tailscale status --json | jq -r '.Peer[] | select(.HostName == "iotpilot-server") | .TailscaleIPs[0]')
        if [ -z "$SERVER_ADDRESS" ] || [ "$SERVER_ADDRESS" = "null" ]; then
            SERVER_ADDRESS="$IOTPILOT_SERVER"
        fi
    else
        SERVER_ADDRESS="$IOTPILOT_SERVER"
    fi

    # Create Promtail configuration
    mkdir -p /etc/promtail
    cat > /etc/promtail/config.yml << EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://$SERVER_ADDRESS:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          device_id: $DEVICE_ID
          device_type: $DEVICE_TYPE
          __path__: /var/log/*log

  - job_name: iotpilot-app
    static_configs:
      - targets:
          - localhost
        labels:
          job: iotpilot
          device_id: $DEVICE_ID
          device_type: $DEVICE_TYPE
          __path__: /opt/iotpilot/app/*.log

  - job_name: systemd
    journal:
      max_age: 12h
      labels:
        job: systemd-journal
        device_id: $DEVICE_ID
        device_type: $DEVICE_TYPE
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
EOF

    # Create systemd service for Promtail
    cat > /etc/systemd/system/promtail.service << 'EOF'
[Unit]
Description=Promtail service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/promtail -config.file /etc/promtail/config.yml
Restart=on-failure
RestartSec=20
StandardOutput=journal
StandardError=journal
SyslogIdentifier=promtail

[Install]
WantedBy=multi-user.target
EOF

    # Start and enable Promtail
    systemctl daemon-reload
    systemctl enable promtail
    systemctl restart promtail

    info "Promtail configured and started"
}

# Create IotPilot device agent
create_device_agent() {
    header "Creating IotPilot device agent..."

    # Create the agent script
    cat > /usr/local/bin/iotpilot-agent << EOF
#!/bin/bash
# IotPilot Device Agent - Reports device status to central server

IOTPILOT_SERVER="$IOTPILOT_SERVER"
DEVICE_ID="$DEVICE_ID"
DEVICE_TOKEN="$DEVICE_TOKEN"

# Function to get server address (Tailscale preferred)
get_server_address() {
    if command -v tailscale &> /dev/null && tailscale status &> /dev/null; then
        SERVER_IP=\$(tailscale status --json | jq -r '.Peer[] | select(.HostName == "iotpilot-server") | .TailscaleIPs[0]')
        if [ -n "\$SERVER_IP" ] && [ "\$SERVER_IP" != "null" ]; then
            echo "http://\$SERVER_IP:3000"
            return
        fi
    fi
    echo "https://\$IOTPILOT_SERVER"
}

# Function to collect device metrics
collect_device_metrics() {
    # Get CPU temperature
    CPU_TEMP=0
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        CPU_TEMP=\$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
    fi

    # Get memory usage
    MEMORY_INFO=\$(free -m | awk 'NR==2{printf "%.1f,%.1f,%.1f", \$3*100/\$2, \$3, \$2}')
    MEMORY_PERCENT=\$(echo \$MEMORY_INFO | cut -d',' -f1)
    MEMORY_USED=\$(echo \$MEMORY_INFO | cut -d',' -f2)
    MEMORY_TOTAL=\$(echo \$MEMORY_INFO | cut -d',' -f3)

    # Get disk usage
    DISK_INFO=\$(df -h / | awk 'NR==2{printf "%s,%s,%s", \$5, \$3, \$2}')
    DISK_PERCENT=\$(echo \$DISK_INFO | cut -d',' -f1 | tr -d '%')
    DISK_USED=\$(echo \$DISK_INFO | cut -d',' -f2)
    DISK_TOTAL=\$(echo \$DISK_INFO | cut -d',' -f3)

    # Get CPU usage (5-second average)
    CPU_USAGE=\$(top -bn1 | grep "Cpu(s)" | awk '{print \$2}' | awk -F'%' '{print \$1}')
    if [ -z "\$CPU_USAGE" ]; then
        CPU_USAGE=\$(top -bn2 -d1 | grep "Cpu(s)" | tail -1 | awk '{print \$2}' | awk -F'%' '{print \$1}')
    fi

    # Get load average
    LOAD_AVERAGE=\$(uptime | awk -F'load average:' '{print \$2}' | tr -d ' ')

    # Get network info
    IP_ADDRESS=\$(hostname -I | awk '{print \$1}')
    TAILSCALE_IP=""
    if command -v tailscale &> /dev/null; then
        TAILSCALE_IP=\$(tailscale ip -4 2>/dev/null || echo "")
    fi

    # Check if main application is running
    APP_STATUS="unknown"
    if systemctl is-active --quiet iotpilot 2>/dev/null; then
        APP_STATUS="running"
    elif [ -f /opt/iotpilot/app/server.js ]; then
        APP_STATUS="stopped"
    else
        APP_STATUS="not_installed"
    fi

    # Create JSON payload
    cat << JSON_EOF
{
  "device_id": "\$DEVICE_ID",
  "hostname": "\$(hostname)",
  "device_type": "$DEVICE_TYPE",
  "device_model": "$DEVICE_MODEL",
  "architecture": "$ARCH",
  "location": "$DEVICE_LOCATION",
  "ip_address": "\$IP_ADDRESS",
  "tailscale_ip": "\$TAILSCALE_IP",
  "uptime": "\$(uptime -p)",
  "load_average": "\$LOAD_AVERAGE",
  "cpu_usage": "\$CPU_USAGE",
  "cpu_temperature": \$CPU_TEMP,
  "memory_usage_percent": \$MEMORY_PERCENT,
  "memory_used_mb": \$MEMORY_USED,
  "memory_total_mb": \$MEMORY_TOTAL,
  "disk_usage_percent": \$DISK_PERCENT,
  "disk_used": "\$DISK_USED",
  "disk_total": "\$DISK_TOTAL",
  "app_status": "\$APP_STATUS",
  "agent_version": "1.0.0",
  "last_boot": "\$(uptime -s)",
  "timestamp": "\$(date -Iseconds)"
}
JSON_EOF
}

# Function to report device status
report_device_status() {
    SERVER_URL=\$(get_server_address)
    DEVICE_DATA=\$(collect_device_metrics)

    # Send to IotPilot server
    HTTP_STATUS=\$(curl -w "%{http_code}" -o /dev/null -s \\
         -X POST "\$SERVER_URL/api/devices/heartbeat" \\
         -H "Content-Type: application/json" \\
         -H "Authorization: Bearer \$DEVICE_TOKEN" \\
         -H "User-Agent: IotPilot-Agent/1.0.0" \\
         -d "\$DEVICE_DATA" \\
         --max-time 15 \\
         --connect-timeout 10)

    if [ "\$HTTP_STATUS" = "200" ] || [ "\$HTTP_STATUS" = "201" ]; then
        echo "\$(date): Successfully reported to \$SERVER_URL"
    else
        echo "\$(date): Failed to report to \$SERVER_URL (HTTP \$HTTP_STATUS)"
    fi
}

# Main execution
case "\$1" in
    "test")
        echo "Testing device agent..."
        collect_device_metrics | jq . 2>/dev/null || collect_device_metrics
        ;;
    "status")
        echo "Device ID: \$DEVICE_ID"
        echo "Server: \$(get_server_address)"
        echo "Last report: \$(tail -1 /var/log/iotpilot-agent.log 2>/dev/null || echo 'No reports yet')"
        ;;
    *)
        report_device_status >> /var/log/iotpilot-agent.log 2>&1
        ;;
esac
EOF

    chmod +x /usr/local/bin/iotpilot-agent

    # Create log file
    touch /var/log/iotpilot-agent.log

    # Test the agent
    info "Testing device agent..."
    /usr/local/bin/iotpilot-agent test

    # Create cron job for regular reporting (every 5 minutes)
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/iotpilot-agent") | crontab -

    # Create systemd timer as backup (more reliable)
    cat > /etc/systemd/system/iotpilot-agent.service << 'EOF'
[Unit]
Description=IotPilot Device Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/iotpilot-agent
User=root
StandardOutput=append:/var/log/iotpilot-agent.log
StandardError=append:/var/log/iotpilot-agent.log
EOF

    cat > /etc/systemd/system/iotpilot-agent.timer << 'EOF'
[Unit]
Description=Run IotPilot Device Agent every 5 minutes
Requires=iotpilot-agent.service

[Timer]
Unit=iotpilot-agent.service
OnBootSec=60s
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable iotpilot-agent.timer
    systemctl start iotpilot-agent.timer

    info "Device agent created and scheduled"
}

# Register device with server
register_device() {
    header "Registering device with IotPilot server..."

    # Try to register the device
    if command -v tailscale &> /dev/null && tailscale status &> /dev/null; then
        SERVER_IP=$(tailscale status --json | jq -r '.Peer[] | select(.HostName == "iotpilot-server") | .TailscaleIPs[0]')
        if [ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "null" ]; then
            SERVER_URL="http://$SERVER_IP:3000"
        else
            SERVER_URL="https://$IOTPILOT_SERVER"
        fi
    else
        SERVER_URL="https://$IOTPILOT_SERVER"
    fi

    REGISTRATION_DATA=$(cat << EOF
{
  "device_id": "$DEVICE_ID",
  "hostname": "$(hostname)",
  "device_type": "$DEVICE_TYPE",
  "device_model": "$DEVICE_MODEL",
  "architecture": "$ARCH",
  "location": "$DEVICE_LOCATION",
  "ip_address": "$(hostname -I | awk '{print $1}')",
  "auto_registered": true,
  "registration_time": "$(date -Iseconds)"
}
EOF
)

    info "Attempting to register with: $SERVER_URL"

    HTTP_STATUS=$(curl -w "%{http_code}" -o /tmp/registration_response.json -s \
         -X POST "$SERVER_URL/api/devices/register" \
         -H "Content-Type: application/json" \
         -H "User-Agent: IotPilot-Agent/1.0.0" \
         -d "$REGISTRATION_DATA" \
         --max-time 15 \
         --connect-timeout 10)

    if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ]; then
        info "Device registered successfully!"
        if [ -f /tmp/registration_response.json ]; then
            cat /tmp/registration_response.json | jq . 2>/dev/null || cat /tmp/registration_response.json
        fi
    else
        warn "Device registration failed (HTTP $HTTP_STATUS). Device will still report metrics."
        if [ -f /tmp/registration_response.json ]; then
            cat /tmp/registration_response.json
        fi
    fi

    rm -f /tmp/registration_response.json
}

# Update existing installation scripts
update_existing_scripts() {
    header "Updating existing IotPilot installation scripts..."

    # Function to add agent installation to existing scripts
    add_agent_to_script() {
        local script_path="$1"
        local script_name="$2"

        if [ -f "$script_path" ]; then
            info "Found $script_name, updating..."
            if ! grep -q "install_iotpilot_agent" "$script_path"; then
                cat >> "$script_path" << 'AGENT_EOF'

# Install IotPilot Device Agent
install_iotpilot_agent() {
    info "Installing IotPilot Device Agent..."
    curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/device-agent-install.sh | \
        IOTPILOT_SERVER="$IOTPILOT_SERVER" \
        TAILSCALE_AUTH_KEY="$TAILSCALE_AUTH_KEY" \
        DEVICE_LOCATION="$DEVICE_LOCATION" \
        bash
}

# Add to main installation function
install_iotpilot_agent
AGENT_EOF
                info "Updated $script_name with agent installation"
            else
                info "$script_name already includes agent installation"
            fi
        fi
    }

    # Update known installation scripts
    add_agent_to_script "/root/autoinstaller-pi-zero-armv6.sh" "Pi Zero installer script"
    add_agent_to_script "/root/autoinstaller-pi-3-aarch64.sh" "Pi 3/4 installer script"
    add_agent_to_script "/opt/iotpilot/scripts/autoinstaller-pi-zero-armv6.sh" "Pi Zero installer (iotpilot dir)"
    add_agent_to_script "/opt/iotpilot/scripts/autoinstaller-pi-3-aarch64.sh" "Pi 3/4 installer (iotpilot dir)"
}

# Show final information
show_final_info() {
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}   IotPilot Device Agent Installation Complete   ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo "🎉 Device agent successfully installed!"
    echo ""
    echo "📊 Device Information:"
    echo "  • Device ID: $DEVICE_ID"
    echo "  • Device Type: $DEVICE_TYPE"
    echo "  • Model: $DEVICE_MODEL"
    echo "  • Architecture: $ARCH"
    echo ""
    echo "🔗 Connection:"
    echo "  • IotPilot Server: $IOTPILOT_SERVER"
    echo "  • Reporting Interval: Every 5 minutes"
    echo ""
    echo "📈 Monitoring:"
    echo "  • Metrics: Telegraf → InfluxDB"
    echo "  • Logs: Promtail → Loki"
    echo "  • Status: Device Agent → API"
    echo ""
    echo "🛠️ Management Commands:"
    echo "  • iotpilot-agent test    - Test agent functionality"
    echo "  • iotpilot-agent status  - Show agent status"
    echo "  • systemctl status iotpilot-agent.timer - Check timer status"
    echo "  • tail -f /var/log/iotpilot-agent.log - View agent logs"
    echo ""
    echo "📁 Configuration Files:"
    echo "  • Telegraf: /etc/telegraf/telegraf.conf"
    echo "  • Promtail: /etc/promtail/config.yml"
    echo "  • Agent: /usr/local/bin/iotpilot-agent"
    echo ""
    echo "🔧 Next Steps:"
    echo "  1. Check agent status: iotpilot-agent status"
    echo "  2. View logs: tail -f /var/log/iotpilot-agent.log"
    echo "  3. Verify device appears in your IotPilot dashboard"
    echo ""
    echo "Your device is now connected to the IotPilot management system!"
    echo ""
}

# Main installation function
main() {
    echo ""
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE}   IotPilot Device Agent Installer   ${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo ""

    info "Installing IotPilot device monitoring agent..."
    info "This will add monitoring capabilities to your device"
    echo ""

    detect_device_type
    install_tailscale
    install_telegraf
    install_promtail
    create_device_agent
    register_device
    update_existing_scripts
    show_final_info
}

# Run main installation
main

exit 0