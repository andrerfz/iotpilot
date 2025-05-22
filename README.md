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

IotPilot is optimized to run on Raspberry Pi devices with dedicated installers for different architectures:

### Raspberry Pi Zero Installation (ARM32/armv6)

For Raspberry Pi Zero, Zero W, and other ARMv6-based devices:

1. Ensure your Raspberry Pi Zero is running Debian Bookworm
2. Install using the auto-installer script:

   ```bash
   # Basic installation
   curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero-armv6.sh | sudo bash

   # Or with Tailscale for remote access
   curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero-armv6.sh | sudo TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash

   # Or with Tailscale and custom hostname
   curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-zero-armv6.sh | sudo TAILSCALE_HOSTNAME="custom-name" TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash
   ```

3. Access your IotPilot instance:
   - Locally: http://iotpilot.local
   - API Documentation: http://iotpilot.local/api-docs
   - Via Tailscale (if configured): https://your-hostname.tailnet-name.ts.net

**Technical Details:**
- Uses Node.js 16.20.2 specifically built for ARMv6 architecture
- Pre-compiled node_modules to avoid build issues on low-memory devices
- Optimized for the limited resources of Pi Zero (512MB RAM)
- Includes Traefik reverse proxy configured for ARMv6

### Raspberry Pi 3/4 Installation (ARM64/aarch64)

For Raspberry Pi 3, Pi 4, and other ARM64-based devices:

1. Ensure your Raspberry Pi is running a 64-bit OS (Debian Bookworm 64-bit recommended)
2. Install using the ARM64-specific auto-installer script:

   ```bash
   # Basic installation
   curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-3-aarch64.sh | sudo bash

   # Or with Tailscale for remote access
   curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-3-aarch64.sh | sudo TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash

   # Or with Tailscale and custom hostname
   curl -sSL https://raw.githubusercontent.com/andrerfz/iotpilot/main/scripts/autoinstaller-pi-3-aarch64.sh | sudo TAILSCALE_HOSTNAME="custom-name" TAILSCALE_AUTH_KEY="tskey-auth-xxxx" bash
   ```

3. Access your IotPilot instance (same as Pi Zero):
   - Locally: http://iotpilot.local
   - API Documentation: http://iotpilot.local/api-docs
   - Via Tailscale (if configured): https://your-hostname.tailnet-name.ts.net

**Technical Details:**
- Uses Node.js 16.x from the NodeSource repository optimized for ARM64
- Pre-compiled node_modules for ARM64 architecture
- Better performance than ARMv6 due to 64-bit architecture and more resources
- Includes additional Tailscale auto-fix service for improved remote access
- Traefik configured for ARM64 architecture

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

### Building for Different Architectures

IotPilot includes build scripts to create pre-compiled node_modules packages for different Raspberry Pi architectures:

#### For Raspberry Pi Zero (ARMv6)

```bash
# From the project root
cd docker/node
./build-for-pi-zero.sh
```

This creates a pre-compiled package at `packages/armv6/node_modules.tar.gz` optimized for ARMv6 architecture.

#### For Raspberry Pi 3/4 (ARM64/aarch64)

```bash
# From the project root
cd docker/node
./build-for-pi-3-arm64.sh
```

This creates a pre-compiled package at `packages/arm64v8/node_modules.tar.gz` optimized for ARM64 architecture.

Both build scripts use Docker with cross-platform emulation to build the packages, so they can be run on any system with Docker installed, regardless of the host architecture.

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
