const express = require('express');
const app = express();
const HTTP_PORT = 4000;
const path = require('path');

// Import Swagger
const { swaggerSpec, swaggerUi, swaggerUiOptions } = require('./swagger');

// Import database and device manager
const { initDatabase } = require('./db');
const deviceManager = require('./deviceManager');

// Import utility functions for scale commands
const scaleCommands = require('./scaleCommands');

// Get hostname from environment
const HOST_NAME = process.env.HOST_NAME || 'localhost';

// CORS middleware to allow API access from other domains when needed
app.use((req, res, next) => {
    // Allow requests from the same hostname served via HTTPS and Tailscale
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    next();
});

// Middleware
app.use(express.static('public'));
app.use(express.json());

// Create data directory for SQLite
const fs = require('fs');
const dataDir = path.join(__dirname, 'data');
if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir);
}

// Ensure the devices directory exists in public
const devicesDir = path.join(__dirname, 'public', 'devices');
if (!fs.existsSync(devicesDir)) {
    fs.mkdirSync(devicesDir, { recursive: true });
}

// Serve Swagger documentation
app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec, swaggerUiOptions));

// Initialize database
initDatabase().then((success) => {
    if (success) {
        console.log('Database initialized successfully');
    } else {
        console.warn('Database initialization had issues, but server will continue with limited functionality');
    }
}).catch((error) => {
    console.error('Fatal database error:', error);
    // Continue execution but with warnings
});

// Add this error handler to your server.js to handle database errors gracefully
app.use((err, req, res, next) => {
    console.error('Error handling request:', err.stack);

    // Check if error is database related
    if (err.message && (
        err.message.includes('database') ||
        err.message.includes('sqlite') ||
        err.message.includes('SQL')
    )) {
        return res.status(500).json({
            error: 'Database error occurred',
            message: 'The server encountered a database issue. This may be due to resource constraints on the Raspberry Pi. Try restarting the service.'
        });
    }

    // Generic error response
    res.status(500).json({
        error: 'Internal server error',
        message: process.env.NODE_ENV === 'development' ? err.message : 'An unexpected error occurred'
    });
});

// Device API endpoints
app.get('/api/devices', async (req, res) => {
    try {
        const devices = await deviceManager.getAllDevices();
        res.json(devices);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/devices/:id', async (req, res) => {
    try {
        const device = await deviceManager.getDevice(req.params.id);
        if (!device) {
            return res.status(404).json({ error: 'Device not found' });
        }
        res.json(device);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/devices', async (req, res) => {
    try {
        const device = await deviceManager.addDevice(req.body);
        res.status(201).json(device);
    } catch (error) {
        res.status(400).json({ error: error.message });
    }
});

app.put('/api/devices/:id', async (req, res) => {
    try {
        const device = await deviceManager.updateDevice(req.params.id, req.body);
        res.json(device);
    } catch (error) {
        res.status(400).json({ error: error.message });
    }
});

app.delete('/api/devices/:id', async (req, res) => {
    try {
        await deviceManager.deleteDevice(req.params.id);
        res.status(204).send();
    } catch (error) {
        res.status(400).json({ error: error.message });
    }
});

// IP-based scale operation endpoints
app.get('/api/devices/:ip/weight', async (req, res) => {
    try {
        // Normalize the IP address (trim whitespace)
        const ip = req.params.ip.trim();
        console.log(`Processing weight request for IP: ${ip}`);

        const device = await deviceManager.findDeviceByIP(ip);
        if (!device) {
            console.log(`Device with IP ${ip} not found in database`);
            return res.status(404).json({ type: 'error', error: 'Device with specified IP not found' });
        }

        console.log(`Found device with ID ${device.id} for IP ${ip}`);
        const result = await deviceManager.sendCommand(device.id, scaleCommands.weightCmd);
        res.json(result);
    } catch (error) {
        console.error(`Error processing weight request: ${error.message}`);
        res.status(400).json({ type: 'error', error: error.message });
    }
});

app.get('/api/devices/:ip/tare', async (req, res) => {
    try {
        const ip = req.params.ip.trim();
        console.log(`Processing tare request for IP: ${ip}`);

        const device = await deviceManager.findDeviceByIP(ip);
        if (!device) {
            return res.status(404).json({ type: 'error', error: 'Device with specified IP not found' });
        }

        res.json(await deviceManager.sendCommand(device.id, scaleCommands.tareCmd));
    } catch (error) {
        res.status(400).json({ type: 'error', error: error.message });
    }
});

app.get('/api/devices/:ip/status', async (req, res) => {
    try {
        const ip = req.params.ip.trim();
        console.log(`Processing status request for IP: ${ip}`);

        const device = await deviceManager.findDeviceByIP(ip);
        if (!device) {
            return res.status(404).json({ type: 'error', error: 'Device with specified IP not found' });
        }

        res.json(await deviceManager.sendCommand(device.id, scaleCommands.statusCmd));
    } catch (error) {
        res.status(400).json({ type: 'error', error: error.message });
    }
});

app.get('/api/devices/:ip/clearPreset', async (req, res) => {
    try {
        const ip = req.params.ip.trim();
        console.log(`Processing clearPreset request for IP: ${ip}`);

        const device = await deviceManager.findDeviceByIP(ip);
        if (!device) {
            return res.status(404).json({ type: 'error', error: 'Device with specified IP not found' });
        }

        res.json(await deviceManager.sendCommand(device.id, scaleCommands.clearPresetTareCmd));
    } catch (error) {
        res.status(400).json({ type: 'error', error: error.message });
    }
});

app.get('/api/devices/:ip/presetTare', async (req, res) => {
    try {
        const ip = req.params.ip.trim();
        console.log(`Processing presetTare request for IP: ${ip}`);

        const device = await deviceManager.findDeviceByIP(ip);
        if (!device) {
            return res.status(404).json({ type: 'error', error: 'Device with specified IP not found' });
        }

        const value = req.query.value;
        if (!value) {
            return res.status(400).json({ type: 'error', error: 'Value query parameter required' });
        }

        const presetTareCmd = scaleCommands.createPresetTareCmd(value);
        res.json(await deviceManager.sendCommand(device.id, presetTareCmd));
    } catch (error) {
        res.status(400).json({ type: 'error', error: error.message });
    }
});

// Bind to all interfaces (0.0.0.0) instead of just the hostname
app.listen(HTTP_PORT, '0.0.0.0', () => {

    console.info(`For developtment server is :`);
    console.log(`Access the server securely via https://${HOST_NAME}:4443`);
    console.log(`Access the server insecurely via http://${HOST_NAME}:4080`);
    console.log(`API documentation available at http://${HOST_NAME}:4080/api-docs`);

    console.info('For production server:');
    console.log(`Access the server securely via https://${HOST_NAME}`);
    console.log(`Access the server insecurely via http://${HOST_NAME}`);
    console.log(`API documentation available at http://${HOST_NAME}/api-docs`);
});