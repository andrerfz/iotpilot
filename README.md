# IotPilot

Micro server designed to provide a bridge connection from App throw IoT devices on local host, providing full remote management and scalability.

🔵Initial focus will be on scale devices, then progressively provide more devices support.

## Project Overview

### Key Features

- **Multi-Device Management**: Configure and manage multiple IoT devices from a single interface
- **Secure Remote Access**: Access your IoT devices from anywhere through Tailscale or localhost
- **Easy Deployment**: Simple Docker-based deployment process
- **API-First Design**: RESTful API for all device operations
- **User-Friendly Interface**: Web-based control panel for device management

## Quick Start

1. Clone this repository
2. Configure environment files:
    - Copy `.env.example` to `.env` and update with your domain
3. Run with Docker Compose:
   ```
   make deploy
   ```
4. Access the interface at ??

## Application Architecture

The application consists of the following components:

### Server Components

- **Device Manager**: Handles device configuration, persistence, and selection
- **TCP Connection Manager**: Manages low-level communication with IoT devices
- **REST API**: Provides HTTP endpoints for web client interaction
- **Static File Server**: Serves the web interface

### Frontend Components

- **Device Control Panel**: Interface for sending commands to selected devices
- **Device Manager Panel**: Interface for adding, editing, and removing devices

### Integration Components

- Steal need define

## Project Status

The project is fully functional with the following features implemented:

✅ HF2211 Scale Communication
✅ Multi-Device Management
✅ Device Configuration Persistence
✅ Secure Remote Access
✅ User-Friendly Web Interface

## Next Steps

- Add support for additional IoT device types
- Implement user authentication
- Add data logging and visualization
- Develop mobile application
- Create a webhook system for integration with other systems

## API Reference

### Device Control Endpoints

- `GET /weight?deviceId=<id>` - Get current weight reading
- `GET /tare?deviceId=<id>` - Tare the scale
- `GET /status?deviceId=<id>` - Get device status
- `GET /clearPreset?deviceId=<id>` - Clear preset tare
- `GET /presetTare?value=<kg>&deviceId=<id>` - Set preset tare

### Device Management Endpoints

- `GET /api/devices` - List all configured devices
- `GET /api/devices/:id` - Get a specific device
- `POST /api/devices` - Add a new device
- `PUT /api/devices/:id` - Update a device
- `DELETE /api/devices/:id` - Remove a device

## Docker Components

The application is deployed using Docker Compose with the following services:

- **iot-app**: The Node.js application

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.