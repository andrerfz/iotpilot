const express = require('express');
const app = express();
const HTTP_PORT = 4000;
const path = require('path');

// Import Swagger
const { swaggerSpec, swaggerUi } = require('./swagger');

// Import database and device manager
const { initDatabase } = require('./db');
const deviceManager = require('./deviceManager');

// Import utility functions for scale commands
const scaleCommands = require('./scaleCommands');

// Get hostname from environment
const HOST_NAME = process.env.HOST_NAME || 'localhost';

// CORS middleware to allow API access from other domains when needed
app.use((req, res, next) => {
    // Allow requests from the same hostname served via HTTPS
    res.setHeader('Access-Control-Allow-Origin', `https://${HOST_NAME}`);
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
app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec, {
    explorer: true,
    customCss: '.swagger-ui .topbar { display: none }'
}));

// Initialize database
initDatabase();

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

// Scale operation endpoints - updated to use deviceId
app.get('/weight', async (req, res) => {
    try {
        const deviceId = req.query.deviceId || 1; // Default to first device if not specified
        res.json(await deviceManager.sendCommand(deviceId, scaleCommands.weightCmd));
    } catch (error) {
        res.status(400).json({ type: 'error', error: error.message });
    }
});

app.get('/tare', async (req, res) => {
    try {
        const deviceId = req.query.deviceId || 1;
        res.json(await deviceManager.sendCommand(deviceId, scaleCommands.tareCmd));
    } catch (error) {
        res.status(400).json({ type: 'error', error: error.message });
    }
});

app.get('/status', async (req, res) => {
    try {
        const deviceId = req.query.deviceId || 1;
        res.json(await deviceManager.sendCommand(deviceId, scaleCommands.statusCmd));
    } catch (error) {
        res.status(400).json({ type: 'error', error: error.message });
    }
});

app.get('/clearPreset', async (req, res) => {
    try {
        const deviceId = req.query.deviceId || 1;
        res.json(await deviceManager.sendCommand(deviceId, scaleCommands.clearPresetTareCmd));
    } catch (error) {
        res.status(400).json({ type: 'error', error: error.message });
    }
});

app.get('/presetTare', async (req, res) => {
    try {
        const deviceId = req.query.deviceId || 1;
        const value = req.query.value;
        if (!value) {
            return res.status(400).json({ type: 'error', error: 'Value query parameter required' });
        }
        const presetTareCmd = scaleCommands.createPresetTareCmd(value);
        res.json(await deviceManager.sendCommand(deviceId, presetTareCmd));
    } catch (error) {
        res.status(400).json({ type: 'error', error: error.message });
    }
});

// Server info endpoint - useful for checking connectivity
app.get('/server-info', (req, res) => {
    res.json({
        hostname: HOST_NAME,
        serverTime: new Date().toISOString(),
        version: require('./package.json').version,
        status: 'running'
    });
});

app.listen(HTTP_PORT, () => {
    console.log(`Server running at http://${HOST_NAME}:${HTTP_PORT}`);
    console.log(`API documentation available at http://${HOST_NAME}:${HTTP_PORT}/api-docs`);
    console.log(`Access the server securely via https://${HOST_NAME}`);
});