# IotPilot

IotPilot is a lightweight server application designed to bridge the gap between your applications and IoT devices on your local network. It provides a clean, unified API for remote device management, monitoring, and control.

![IotPilot Logo](https://via.placeholder.com/200x200?text=IotPilot)

## 🔷 Project Overview

IotPilot serves as a middleware solution that allows you to:

1. **Connect to IoT devices on your local network** through a standardized RESTful API
2. **Manage devices remotely** through secure Tailscale networking
3. **Access devices from any platform** (web, mobile apps, etc.) using simple HTTP requests
4. **Scale your IoT infrastructure** by adding multiple devices of various types

The initial focus is on scale devices (specifically the HF2211 protocol), with plans to expand support to more device types in the future.

## ✨ Key Features

- **Multi-Device Management**: Configure and manage multiple IoT devices from a single interface
- **Secure Remote Access**: Access your IoT devices from anywhere through Tailscale or localhost
- **Easy Deployment**: Simple Docker-based deployment for development or direct installation for Raspberry Pi
- **API-First Design**: Clean RESTful API for all device operations
- **User-Friendly Interface**: Web-based control panel for device management

## 🚀 Quick Start (Development)

For local development on your computer:

1. Clone this repository
   ```
   git clone https://github.com/andrerfz/iotpilot.git
   cd iotpilot
   ```

2. Configure environment files:
   ```
   cp .env.example .env
   ```
   Update the `.env` file with your settings (domain, Tailscale auth key, etc.)

3. Generate local SSL certificates for development:
   ```
   make generate-certs
   ```

4. Run with Docker Compose:
   ```
   make deploy
   ```

5. Access the interface at:
   - HTTP: http://iotpilot.test:4080
   - HTTPS: https://iotpilot.test:4443
   - API Documentation: http://iotpilot.test:4080/api-docs

## 📱 Production Deployment (Raspberry Pi)

IotPilot is optimized to run on Raspberry Pi devices, including the resource-constrained Pi Zero:

### Raspberry Pi Zero Installation

1. Ensure your Raspberry Pi Zero is running Debian Bookworm
2. Install using the auto-installer script:

   ```bash
   # Basic installation
   curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero-armv6.sh | sudo bash
   
   # Or with Tailscale for remote access
   curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero-armv6.sh | sudo TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash
   ```

3. Access your IotPilot instance:
   - Locally: http://iotpilot.local
   - API Documentation: http://iotpilot.local/api-docs
   - Via Tailscale (if configured): https://your-hostname.tailnet-name.ts.net

### Other Raspberry Pi Models

The installation process is the same as for Pi Zero, but with better performance.

## 🔌 Supported Devices

Currently supported devices:

- **Scales**: HF2211 protocol compatible scales (and similar)

Planned support for additional device types:

- Thermostats
- Relays
- Sensors
- And more...

## 🔧 API Reference

### Device Management Endpoints

- `GET /api/devices` - List all configured devices
- `GET /api/devices/:id` - Get a specific device
- `POST /api/devices` - Add a new device
- `PUT /api/devices/:id` - Update a device
- `DELETE /api/devices/:id` - Remove a device

### Device Control Endpoints (IP-based, recommended)

- `GET /api/devices/:ip/weight` - Get current weight reading
- `GET /api/devices/:ip/tare` - Tare the scale
- `GET /api/devices/:ip/status` - Get device status
- `GET /api/devices/:ip/clearPreset` - Clear preset tare
- `GET /api/devices/:ip/presetTare?value=<kg>` - Set preset tare

For complete API documentation, visit `/api-docs` on your IotPilot server.

## 🧰 Architecture

The application consists of the following components:

### Server Components

- **Device Manager**: Handles device configuration, persistence, and selection
- **TCP Connection Manager**: Manages low-level communication with IoT devices
- **REST API**: Provides HTTP endpoints for web client interaction
- **Static File Server**: Serves the web interface

### Frontend Components

- **Device Control Panel**: Interface for sending commands to selected devices
- **Device Manager Panel**: Interface for adding, editing, and removing devices

## 🔮 Next Steps

- Add support for additional IoT device types
- Implement user authentication
- Add data logging and visualization
- Develop mobile application
- Create a webhook system for integration with other systems

## 👥 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.