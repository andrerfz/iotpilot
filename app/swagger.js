const swaggerJsdoc = require('swagger-jsdoc');
const swaggerUi = require('swagger-ui-express');

// Get hostname from environment or default to iotpilot.test
const HOST_NAME = process.env.HOST_NAME || 'iotpilot.test';
const NODE_ENV = process.env.NODE_ENV || 'development';

// Determine if we're in development mode
const isDev = NODE_ENV === 'development';

// Define servers array dynamically
let servers = [];

// Always add the current server as the first option
servers.push({
    url: '/',
    description: 'Current server'
});

// Add development and production servers
if (isDev) {
    servers.push(
        {
            url: `http://${HOST_NAME}:4080`,
            description: 'Development server (HTTP)'
        },
        {
            url: `https://${HOST_NAME}:4443`,
            description: 'Development server (HTTPS)'
        }
    );
} else {
    servers.push(
        {
            url: `http://${HOST_NAME}`,
            description: 'Production server (HTTP)'
        },
        {
            url: `https://${HOST_NAME}`,
            description: 'Production server (HTTPS)'
        }
    );
}

const options = {
    definition: {
        openapi: '3.0.0',
        info: {
            title: 'IoT Pilot API',
            version: '1.0.0',
            description: 'API for managing and communicating with IoT devices',
            contact: {
                name: 'IoT Pilot Team'
            },
            license: {
                name: 'MIT',
                url: 'https://opensource.org/licenses/MIT'
            }
        },
        servers: servers,
        components: {
            schemas: {
                Device: {
                    type: 'object',
                    required: ['name', 'type', 'host', 'port'],
                    properties: {
                        id: {
                            type: 'integer',
                            description: 'Unique identifier for the device'
                        },
                        name: {
                            type: 'string',
                            description: 'Name of the device'
                        },
                        type: {
                            type: 'string',
                            description: 'Type of device (e.g., scale, thermostat)'
                        },
                        host: {
                            type: 'string',
                            description: 'IP address or hostname of the device'
                        },
                        port: {
                            type: 'integer',
                            description: 'Port number for device communication'
                        },
                        description: {
                            type: 'string',
                            description: 'Optional description of the device'
                        },
                        active: {
                            type: 'boolean',
                            description: 'Whether the device is active',
                            default: true
                        }
                    }
                },
                Error: {
                    type: 'object',
                    properties: {
                        error: {
                            type: 'string',
                            description: 'Error message'
                        }
                    }
                },
                Response: {
                    type: 'object',
                    properties: {
                        type: {
                            type: 'string',
                            description: 'Response type',
                            enum: ['weight', 'tare', 'status', 'error', 'presetTare', 'clearPreset']
                        },
                        message: {
                            type: 'string',
                            description: 'Response message'
                        },
                        success: {
                            type: 'boolean',
                            description: 'Whether the operation was successful'
                        },
                        error: {
                            type: 'string',
                            description: 'Error message if type is "error"'
                        }
                    }
                },
                WeightResponse: {
                    type: 'object',
                    properties: {
                        type: {
                            type: 'string',
                            enum: ['weight'],
                            description: 'Response type'
                        },
                        gross: {
                            type: 'string',
                            description: 'Gross weight reading'
                        },
                        tare: {
                            type: 'string',
                            description: 'Tare weight'
                        },
                        net: {
                            type: 'number',
                            description: 'Net weight (gross - tare) in kg'
                        },
                        statusFlags: {
                            type: 'object',
                            properties: {
                                zero: {
                                    type: 'boolean',
                                    description: 'Whether scale is at zero'
                                },
                                tare: {
                                    type: 'boolean',
                                    description: 'Whether scale has a tare value'
                                },
                                stable: {
                                    type: 'boolean',
                                    description: 'Whether weight reading is stable'
                                },
                                net: {
                                    type: 'boolean',
                                    description: 'Whether display shows net weight'
                                },
                                tareMode: {
                                    type: 'string',
                                    description: 'Current tare mode',
                                    enum: ['normal', 'preset']
                                },
                                presetTare: {
                                    type: 'boolean',
                                    description: 'Whether preset tare is active'
                                }
                            }
                        },
                        lrcValid: {
                            type: 'boolean',
                            description: 'Whether the checksum is valid'
                        }
                    }
                },
                StatusResponse: {
                    type: 'object',
                    properties: {
                        type: {
                            type: 'string',
                            enum: ['status'],
                            description: 'Response type'
                        },
                        status: {
                            type: 'object',
                            properties: {
                                code: {
                                    type: 'integer',
                                    description: 'Status code'
                                },
                                description: {
                                    type: 'string',
                                    description: 'Status description'
                                }
                            }
                        },
                        lrcValid: {
                            type: 'boolean',
                            description: 'Whether the checksum is valid'
                        }
                    }
                },
                TareResponse: {
                    type: 'object',
                    properties: {
                        type: {
                            type: 'string',
                            enum: ['tare'],
                            description: 'Response type'
                        },
                        message: {
                            type: 'string',
                            description: 'Operation result message'
                        },
                        success: {
                            type: 'boolean',
                            description: 'Whether the tare operation was successful'
                        },
                        lrcValid: {
                            type: 'boolean',
                            description: 'Whether the checksum is valid'
                        }
                    }
                },
                PresetTareResponse: {
                    type: 'object',
                    properties: {
                        type: {
                            type: 'string',
                            enum: ['presetTare', 'clearPreset'],
                            description: 'Response type'
                        },
                        message: {
                            type: 'string',
                            description: 'Operation result message'
                        },
                        success: {
                            type: 'boolean',
                            description: 'Whether the operation was successful'
                        },
                        lrcValid: {
                            type: 'boolean',
                            description: 'Whether the checksum is valid'
                        }
                    }
                }
            }
        },
        tags: [
            {
                name: 'Devices',
                description: 'Device management endpoints'
            },
            {
                name: 'Scale Operations',
                description: 'Scale device operations'
            },
            {
                name: 'IP-based Scale Operations',
                description: 'Scale device operations using IP address (recommended)'
            }
        ]
    },
    apis: ['./server.js', './swagger.js'] // Path to the API docs
};

// Swagger specification
const swaggerSpec = swaggerJsdoc(options);

// Add API route documentation here using JSDoc format
/**
 * @swagger
 * /api/devices:
 *   get:
 *     summary: Get all devices
 *     description: Retrieve a list of all configured devices
 *     tags: [Devices]
 *     responses:
 *       200:
 *         description: A list of devices
 *         content:
 *           application/json:
 *             schema:
 *               type: array
 *               items:
 *                 $ref: '#/components/schemas/Device'
 *       500:
 *         description: Server error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *   post:
 *     summary: Create a new device
 *     description: Add a new device to the system
 *     tags: [Devices]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             $ref: '#/components/schemas/Device'
 *     responses:
 *       201:
 *         description: Device created successfully
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Device'
 *       400:
 *         description: Invalid request
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *
 * /api/devices/{id}:
 *   get:
 *     summary: Get a specific device
 *     description: Retrieve details for a specific device by ID
 *     tags: [Devices]
 *     parameters:
 *       - in: path
 *         name: id
 *         schema:
 *           type: integer
 *         required: true
 *         description: ID of the device to retrieve
 *     responses:
 *       200:
 *         description: Device details
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Device'
 *       404:
 *         description: Device not found
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *   put:
 *     summary: Update a device
 *     description: Update an existing device's configuration
 *     tags: [Devices]
 *     parameters:
 *       - in: path
 *         name: id
 *         schema:
 *           type: integer
 *         required: true
 *         description: ID of the device to update
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             $ref: '#/components/schemas/Device'
 *     responses:
 *       200:
 *         description: Device updated successfully
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Device'
 *       400:
 *         description: Invalid request
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       404:
 *         description: Device not found
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *   delete:
 *     summary: Delete a device
 *     description: Remove a device from the system
 *     tags: [Devices]
 *     parameters:
 *       - in: path
 *         name: id
 *         schema:
 *           type: integer
 *         required: true
 *         description: ID of the device to delete
 *     responses:
 *       204:
 *         description: Device deleted successfully
 *       400:
 *         description: Invalid request
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *
 * /api/devices/{ip}/weight:
 *   get:
 *     summary: Get weight reading by IP
 *     description: Get the current weight reading from a scale device by IP address
 *     tags: [IP-based Scale Operations]
 *     parameters:
 *       - in: path
 *         name: ip
 *         schema:
 *           type: string
 *         required: true
 *         description: IP address of the device
 *     responses:
 *       200:
 *         description: Weight reading
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/WeightResponse'
 *       404:
 *         description: Device with specified IP not found
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       400:
 *         description: Invalid request or device error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *
 * /api/devices/{ip}/tare:
 *   get:
 *     summary: Tare the scale by IP
 *     description: Reset the scale to zero at the current weight by IP address
 *     tags: [IP-based Scale Operations]
 *     parameters:
 *       - in: path
 *         name: ip
 *         schema:
 *           type: string
 *         required: true
 *         description: IP address of the device
 *     responses:
 *       200:
 *         description: Tare operation response
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/TareResponse'
 *       404:
 *         description: Device with specified IP not found
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       400:
 *         description: Invalid request or device error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *
 * /api/devices/{ip}/status:
 *   get:
 *     summary: Get device status by IP
 *     description: Retrieve the current status of a device by IP address
 *     tags: [IP-based Scale Operations]
 *     parameters:
 *       - in: path
 *         name: ip
 *         schema:
 *           type: string
 *         required: true
 *         description: IP address of the device
 *     responses:
 *       200:
 *         description: Device status
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/StatusResponse'
 *       404:
 *         description: Device with specified IP not found
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       400:
 *         description: Invalid request or device error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *
 * /api/devices/{ip}/clearPreset:
 *   get:
 *     summary: Clear preset tare by IP
 *     description: Clear any preset tare value on the scale by IP address
 *     tags: [IP-based Scale Operations]
 *     parameters:
 *       - in: path
 *         name: ip
 *         schema:
 *           type: string
 *         required: true
 *         description: IP address of the device
 *     responses:
 *       200:
 *         description: Clear preset tare operation response
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/PresetTareResponse'
 *       404:
 *         description: Device with specified IP not found
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       400:
 *         description: Invalid request or device error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *
 * /api/devices/{ip}/presetTare:
 *   get:
 *     summary: Set preset tare by IP
 *     description: Set a preset tare value on the scale by IP address
 *     tags: [IP-based Scale Operations]
 *     parameters:
 *       - in: path
 *         name: ip
 *         schema:
 *           type: string
 *         required: true
 *         description: IP address of the device
 *       - in: query
 *         name: value
 *         schema:
 *           type: number
 *           format: float
 *         required: true
 *         description: Tare value to set (in kg)
 *     responses:
 *       200:
 *         description: Set preset tare operation response
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/PresetTareResponse'
 *       404:
 *         description: Device with specified IP not found
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *       400:
 *         description: Invalid request or device error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 */

module.exports = {
    swaggerSpec,
    swaggerUi
};