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

    // Bulk import devices from an exported payload.
    // Dedup by (host, port). On name collision (UNIQUE), auto-rename with " (N)" suffix.
    async importDevices(devices, mode = 'merge') {
        const summary = { added: 0, skipped: 0, renamed: 0, errors: [] };

        if (mode === 'replace') {
            await Device.destroy({ where: {} });
        }

        const existing = mode === 'replace' ? [] : await this.getAllDevices();
        const byHostPort = new Map();
        const names = new Set();
        for (const d of existing) {
            byHostPort.set(`${d.host.trim()}:${d.port}`, d);
            names.add(d.name);
        }

        for (const raw of devices) {
            try {
                if (!raw || !raw.name || !raw.host || raw.port == null) {
                    summary.errors.push({ name: raw?.name || '(sin nombre)', error: 'Faltan campos requeridos (name, host, port)' });
                    continue;
                }

                const key = `${String(raw.host).trim()}:${raw.port}`;
                if (byHostPort.has(key)) {
                    summary.skipped++;
                    continue;
                }

                let name = String(raw.name);
                const wasRenamed = names.has(name);
                if (wasRenamed) {
                    let suffix = 2;
                    while (names.has(`${raw.name} (${suffix})`)) suffix++;
                    name = `${raw.name} (${suffix})`;
                }

                const created = await Device.create({
                    name,
                    type: raw.type || 'scale',
                    host: String(raw.host).trim(),
                    port: Number(raw.port),
                    description: raw.description ?? null,
                    active: raw.active !== false,
                });

                names.add(name);
                byHostPort.set(key, created);
                summary.added++;
                if (wasRenamed) summary.renamed++;
            } catch (err) {
                summary.errors.push({ name: raw?.name || '(sin nombre)', error: err.message });
            }
        }

        return summary;
    }
}

module.exports = new DeviceManager();