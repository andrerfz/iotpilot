const net = require('net');
const { Device } = require('./db');
const scaleCommands = require('./scaleCommands');
const scaleParser = require('./scaleParser');

class DeviceManager {
    constructor() {
        this.activeConnections = {};
    }

    // Get all devices from the database
    async getAllDevices() {
        return await Device.findAll();
    }

    // Get a specific device by ID
    async getDevice(id) {
        return await Device.findByPk(id);
    }

    // Add a new device
    async addDevice(deviceData) {
        return await Device.create(deviceData);
    }

    // Update an existing device
    async updateDevice(id, deviceData) {
        const device = await Device.findByPk(id);
        if (!device) {
            throw new Error('Device not found');
        }
        return await device.update(deviceData);
    }

    // Delete a device
    async deleteDevice(id) {
        const device = await Device.findByPk(id);
        if (!device) {
            throw new Error('Device not found');
        }
        return await device.destroy();
    }

    // Send a command to a specific device
    async sendCommand(deviceId, command) {
        const device = await this.getDevice(deviceId);
        if (!device) {
            throw new Error('Device not found');
        }

        return new Promise((resolve, reject) => {
            const client = new net.Socket();
            let responseData = {};
            let rawResponse = '';

            client.connect(device.port, device.host, () => {
                console.log(`Sending command to ${device.name}:`, command.toString('hex'));
                client.write(command);
            });

            client.on('data', (data) => {
                rawResponse += data.toString('hex');
                console.log('Raw response:', data.toString('hex'));

                // Use the scaleParser to parse the response
                responseData = scaleParser.parseResponse(data, command, rawResponse);

                // Special case for tare command: if successful, send clear preset tare command
                if (responseData.type === 'tare' &&
                    responseData.success &&
                    Buffer.compare(command, scaleCommands.tareCmd) === 0) {
                    console.log('Sending clearPresetTareCmd after successful tare');
                    client.write(scaleCommands.clearPresetTareCmd);
                } else {
                    client.end();
                }
            });

            client.on('error', (err) => {
                responseData.type = 'error';
                responseData.error = err.message;
                client.end();
            });

            client.on('close', () => {
                if (!responseData.type && rawResponse) {
                    responseData.type = 'error';
                    responseData.error = `No response parsed, raw: ${rawResponse}`;
                }
                resolve(responseData);
            });

            setTimeout(() => {
                if (!responseData.type) {
                    responseData.type = 'error';
                    responseData.error = `No response from scale, raw: ${rawResponse || 'none'}`;
                    client.end();
                }
            }, 2000);
        });
    }

    // Find a device by IP address (host)
    async findDeviceByIP(ip) {
        try {
            const devices = await this.getAllDevices();
            // Normalize IP addresses for comparison (trim whitespace)
            const normalizedIp = ip.trim();
            return devices.find(d => d.host.trim() === normalizedIp);
        } catch (error) {
            console.error(`Error finding device by IP: ${error.message}`);
            return null;
        }
    }
}

module.exports = new DeviceManager();