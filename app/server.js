const express = require('express');
const session = require('express-session');
const bcrypt = require('bcryptjs');
const app = express();
const HTTP_PORT = 4000;
const path = require('path');

// Import Swagger
const { swaggerSpec, swaggerUi, swaggerUiOptions } = require('./swagger');

// Import database and device manager
const { initDatabase, Setting } = require('./db');
const deviceManager = require('./deviceManager');

// Import utility functions for scale commands
const scaleCommands = require('./scaleCommands');

// Import auth configuration and middleware
const authConfig = require('./config/auth');
const { requireAuth, AUTH_ENABLED } = require('./middleware/requireAuth');

// Get hostname from environment
const HOST_NAME = process.env.HOST_NAME || 'localhost';
const NODE_ENV = process.env.NODE_ENV || "development";
const SESSION_SECRET = process.env.SESSION_SECRET || 'iotpilot-dev-secret-change-in-production';

// CORS middleware to allow API access from other domains when needed
app.use((req, res, next) => {
    // Allow requests from the same hostname served via HTTPS and Tailscale
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    next();
});

// Middleware
app.use(express.json());

// Session middleware (in-memory store — sessions are lost on restart, which is
// fine for a single-Pi low-volume deployment). Only active when AUTH_ENABLED.
if (AUTH_ENABLED) {
    app.use(session({
        name: authConfig.SESSION_COOKIE_NAME,
        secret: SESSION_SECRET,
        resave: false,
        saveUninitialized: false,
        rolling: true, // Reset maxAge on every request so active users don't get logged out
        cookie: {
            httpOnly: true,
            sameSite: 'lax',
            secure: false, // Served via Traefik; Pi-internal traffic is http
            maxAge: 1000 * 60 * 30, // 30 minutes of inactivity
        },
    }));
}

// Apply requireAuth to protected routes before they're registered.
app.use(requireAuth);

app.use(express.static('public'));

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

// Auth endpoints
app.post('/api/auth/login', async (req, res) => {
    try {
        if (!AUTH_ENABLED) {
            return res.status(400).json({ error: 'Auth is disabled on this deployment' });
        }
        const { user, password } = req.body || {};
        if (!user || !password) {
            return res.status(400).json({ error: 'Missing user or password' });
        }
        // Single-user model: username is always "admin". Reject any other value
        // with a generic 401 so we don't leak which field was wrong.
        if (user !== 'admin') {
            await new Promise((r) => setTimeout(r, 400));
            return res.status(401).json({ error: 'Invalid credentials' });
        }

        // Try master first, then local (stored in Settings).
        let role = null;
        if (await bcrypt.compare(password, authConfig.MASTER_HASH)) {
            role = 'master';
        } else {
            const localHash = await Setting.get('local_password_hash');
            if (localHash && await bcrypt.compare(password, localHash)) {
                role = 'local';
            }
        }

        if (!role) {
            // Small fixed delay to blunt brute-force without proper rate limiting.
            await new Promise((r) => setTimeout(r, 400));
            return res.status(401).json({ error: 'Invalid credentials' });
        }

        req.session.userId = user;
        req.session.role = role;

        if (role === 'master') {
            const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
            console.warn(`[AUTH] Login with master credentials from ${ip} at ${new Date().toISOString()}`);
        }

        res.json({ user, role });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/auth/logout', (req, res) => {
    if (!req.session) return res.json({ ok: true });
    req.session.destroy((err) => {
        if (err) return res.status(500).json({ error: err.message });
        res.clearCookie(authConfig.SESSION_COOKIE_NAME);
        res.json({ ok: true });
    });
});

app.get('/api/auth/me', (req, res) => {
    if (!AUTH_ENABLED) return res.json({ authEnabled: false });
    if (req.session && req.session.userId) {
        return res.json({ authEnabled: true, user: req.session.userId, role: req.session.role });
    }
    res.status(401).json({ authEnabled: true, error: 'Not authenticated' });
});

app.post('/api/auth/change-local-password', async (req, res) => {
    try {
        if (!AUTH_ENABLED) return res.status(400).json({ error: 'Auth is disabled' });
        if (!req.session || !req.session.userId) {
            return res.status(401).json({ error: 'Authentication required' });
        }
        const { newPassword } = req.body || {};
        if (typeof newPassword !== 'string' || newPassword.length < 8) {
            return res.status(400).json({ error: 'Password must be at least 8 characters' });
        }
        const hash = await bcrypt.hash(newPassword, authConfig.BCRYPT_COST);
        await Setting.set('local_password_hash', hash);
        res.json({ ok: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
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

app.get('/api/devices/export', async (req, res) => {
    try {
        const devices = await deviceManager.getAllDevices();
        const payload = {
            exported_at: new Date().toISOString(),
            hostname: HOST_NAME,
            version: require('./package.json').version,
            device_count: devices.length,
            devices,
        };
        const date = new Date().toISOString().slice(0, 10);
        const safeHost = HOST_NAME.replace(/[^a-zA-Z0-9.-]/g, '_');
        const filename = `iotpilot-devices-${safeHost}-${date}.json`;
        res.setHeader('Content-Type', 'application/json; charset=utf-8');
        res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
        res.send(JSON.stringify(payload, null, 2));
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// TODO: secure this endpoint (along with the rest of /api/devices) with auth.
app.post('/api/devices/import', async (req, res) => {
    try {
        const { mode = 'merge', payload } = req.body || {};

        if (mode !== 'merge' && mode !== 'replace') {
            return res.status(400).json({ error: 'Modo inválido: debe ser "merge" o "replace"' });
        }
        if (!payload || !Array.isArray(payload.devices)) {
            return res.status(400).json({ error: 'Formato inválido: se esperaba { payload: { devices: [...] } }' });
        }

        const summary = await deviceManager.importDevices(payload.devices, mode);
        res.json(summary);
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

    if (NODE_ENV === "development") {
        console.info(`For developtment server is :`);
        console.log(`Access the server securely via https://${HOST_NAME}:4443`);
        console.log(`Access the server insecurely via http://${HOST_NAME}:4080`);
        console.log(`API documentation available at http://${HOST_NAME}:4080/api-docs`);
    } else {
        console.info('For production server:');
        console.log(`Access the server securely via https://${HOST_NAME}`);
        console.log(`Access the server insecurely via http://${HOST_NAME}`);
        console.log(`API documentation available at http://${HOST_NAME}/api-docs`);
    }
});