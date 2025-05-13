const swaggerJsdoc = require('swagger-jsdoc');
const swaggerUi = require('swagger-ui-express');

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
        servers: [
            {
                url: 'http://iotpilot.test:4080',
                description: 'Development server'
            },
            {
                url: 'https://iotpilot.test:4443',
                description: 'Development server TLS'
            },
            {
                url: 'http://iotpilot.local',
                description: 'Production server'
            },
            {
                url: 'https://iotpilot.local',
                description: 'Production server TLS'
            }
        ],
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
                            enum: ['weight', 'tare', 'status', 'error']
                        },
                        data: {
                            type: 'object',
                            description: 'Response data (varies by response type)'
                        },
                        error: {
                            type: 'string',
                            description: 'Error message if type is "error"'
                        }
                    }
                },
                WeightResponse: {
                    allOf: [
                        { $ref: '#/components/schemas/Response' },
                        {
                            type: 'object',
                            properties: {
                                data: {
                                    type: 'object',
                                    properties: {
                                        weight: {
                                            type: 'number',
                                            description: 'Current weight reading in kg'
                                        },
                                        unit: {
                                            type: 'string',
                                            description: 'Unit of measurement',
                                            enum: ['kg', 'g']
                                        },
                                        stable: {
                                            type: 'boolean',
                                            description: 'Whether the weight reading is stable'
                                        }
                                    }
                                }
                            }
                        }
                    ]
                },
                StatusResponse: {
                    allOf: [
                        { $ref: '#/components/schemas/Response' },
                        {
                            type: 'object',
                            properties: {
                                data: {
                                    type: 'object',
                                    properties: {
                                        status: {
                                            type: 'string',
                                            description: 'Device status',
                                            enum: ['ready', 'busy', 'error']
                                        },
                                        battery: {
                                            type: 'integer',
                                            description: 'Battery level as percentage (if applicable)'
                                        },
                                        mode: {
                                            type: 'string',
                                            description: 'Current operating mode'
                                        }
                                    }
                                }
                            }
                        }
                    ]
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
 *               $ref: '#/components/schemas/Response'
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
 *               $ref: '#/components/schemas/Response'
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
 *               $ref: '#/components/schemas/Response'
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
 * /weight:
 *   get:
 *     summary: Get weight reading (Legacy)
 *     description: Get the current weight reading from a scale device
 *     tags: [Scale Operations]
 *     parameters:
 *       - in: query
 *         name: deviceId
 *         schema:
 *           type: integer
 *         required: false
 *         description: ID of the device to query (defaults to 1 if not specified)
 *     responses:
 *       200:
 *         description: Weight reading
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/WeightResponse'
 *       400:
 *         description: Invalid request or device error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *
 * /tare:
 *   get:
 *     summary: Tare the scale (Legacy)
 *     description: Reset the scale to zero at the current weight
 *     tags: [Scale Operations]
 *     parameters:
 *       - in: query
 *         name: deviceId
 *         schema:
 *           type: integer
 *         required: false
 *         description: ID of the device to tare (defaults to 1 if not specified)
 *     responses:
 *       200:
 *         description: Tare operation response
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Response'
 *       400:
 *         description: Invalid request or device error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *
 * /status:
 *   get:
 *     summary: Get device status (Legacy)
 *     description: Retrieve the current status of a device
 *     tags: [Scale Operations]
 *     parameters:
 *       - in: query
 *         name: deviceId
 *         schema:
 *           type: integer
 *         required: false
 *         description: ID of the device to query (defaults to 1 if not specified)
 *     responses:
 *       200:
 *         description: Device status
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/StatusResponse'
 *       400:
 *         description: Invalid request or device error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *
 * /clearPreset:
 *   get:
 *     summary: Clear preset tare (Legacy)
 *     description: Clear any preset tare value on the scale
 *     tags: [Scale Operations]
 *     parameters:
 *       - in: query
 *         name: deviceId
 *         schema:
 *           type: integer
 *         required: false
 *         description: ID of the device to clear (defaults to 1 if not specified)
 *     responses:
 *       200:
 *         description: Clear preset tare operation response
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Response'
 *       400:
 *         description: Invalid request or device error
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Error'
 *
 * /presetTare:
 *   get:
 *     summary: Set preset tare (Legacy)
 *     description: Set a preset tare value on the scale
 *     tags: [Scale Operations]
 *     parameters:
 *       - in: query
 *         name: value
 *         schema:
 *           type: number
 *           format: float
 *         required: true
 *         description: Tare value to set (in kg)
 *       - in: query
 *         name: deviceId
 *         schema:
 *           type: integer
 *         required: false
 *         description: ID of the device to set (defaults to 1 if not specified)
 *     responses:
 *       200:
 *         description: Set preset tare operation response
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/Response'
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