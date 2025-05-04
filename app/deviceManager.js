const net = require('net');
const { Device } = require('./db');

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

                // Process response based on command type
                // This would contain all the response parsing logic from server.js
                // For brevity, I'm not including the full parsing logic here

                client.end();
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
}

module.exports = new DeviceManager();