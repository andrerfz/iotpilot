const path = require('path');
const fs = require('fs');
const { DataTypes } = require('sequelize');

// Better SQLite3 Adapter for Sequelize
class BetterSQLiteAdapter {
    constructor() {
        // Dynamically load better-sqlite3 to avoid dependency issues
        try {
            this.sqlite = require('better-sqlite3');
        } catch (error) {
            console.error('Failed to load better-sqlite3, falling back to in-memory mode:', error.message);
            this.sqlite = null;
        }

        this.db = null;
        this.connected = false;
    }

    connect(dbPath) {
        try {
            if (!this.sqlite) {
                throw new Error('better-sqlite3 not available');
            }

            this.db = new this.sqlite(dbPath, {
                verbose: process.env.NODE_ENV === 'development' ? console.log : null,
                fileMustExist: false
            });

            // Test the connection
            this.db.prepare('SELECT 1').get();
            this.connected = true;
            return true;
        } catch (error) {
            console.error('Database connection error:', error.message);
            this.connected = false;
            return false;
        }
    }

    close() {
        if (this.db) {
            this.db.close();
            this.db = null;
            this.connected = false;
        }
    }

    execute(sql, params = []) {
        try {
            if (!this.db) {
                throw new Error('Database not connected');
            }

            if (sql.trim().toUpperCase().startsWith('SELECT')) {
                const stmt = this.db.prepare(sql);
                return stmt.all(...params);
            } else {
                const stmt = this.db.prepare(sql);
                return stmt.run(...params);
            }
        } catch (error) {
            console.error('SQL execution error:', error.message);
            throw error;
        }
    }
}

// Create the database file in the app directory for persistence
const dataDir = path.join(__dirname, '..', 'data');
const dbPath = path.join(dataDir, 'iotpilot.sqlite');
let dbAdapter = new BetterSQLiteAdapter();
let inMemoryMode = false;

// Create a mock Sequelize instance and define function
// This avoids actually initializing Sequelize with a dialect
const sequelize = {
    define: (modelName, attributes, options) => {
        // We're only using this to parse the model definition
        console.log(`Mock Sequelize: Defined model ${modelName}`);
        return {};
    }
};

// Use the device model definition just to document the schema,
// but we'll use our own implementations for database operations
const deviceModel = require('./models/device')(sequelize);

// Track whether we've already created a default device in this session
let defaultDeviceCreated = false;

// Initialize the database
const initDatabase = async () => {
    try {
        // Create data directory if it doesn't exist
        if (!fs.existsSync(dataDir)) {
            fs.mkdirSync(dataDir, { recursive: true });
        }

        // Try to connect to the SQLite database
        const connected = dbAdapter.connect(dbPath);

        if (!connected) {
            console.warn('Using in-memory database mode');
            inMemoryMode = true;
            // Set up in-memory tables
            dbAdapter.connect(':memory:');
        }

        // Create tables if they don't exist
        dbAdapter.execute(`
            CREATE TABLE IF NOT EXISTS Devices (
                                                   id INTEGER PRIMARY KEY AUTOINCREMENT,
                                                   name TEXT NOT NULL UNIQUE,
                                                   type TEXT NOT NULL DEFAULT 'scale',
                                                   host TEXT NOT NULL,
                                                   port INTEGER NOT NULL,
                                                   description TEXT,
                                                   active INTEGER DEFAULT 1,
                                                   createdAt TEXT,
                                                   updatedAt TEXT
            )
        `);

        console.log('Database initialized successfully');

        // Check if we have any devices, if not add a default one
        if (!defaultDeviceCreated) {
            const devices = dbAdapter.execute('SELECT COUNT(*) as count FROM Devices');
            if (devices[0].count === 0) {
                // Add default device
                const now = new Date().toISOString();
                dbAdapter.execute(
                    `INSERT INTO Devices (name, type, host, port, description, active, createdAt, updatedAt)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                    ['Default Scale', 'scale', '192.168.1.11', 9999,
                        inMemoryMode ? 'Default HF2211 scale device (in-memory, will be lost on restart)' : 'Default HF2211 scale device',
                        1, now, now]
                );
                console.log('Default device created');
                defaultDeviceCreated = true;
            } else {
                console.log(`Found ${devices[0].count} existing devices, skipping default device creation`);
            }
        }

        return true;
    } catch (error) {
        console.error('Error initializing database:', error);
        return false;
    }
};

// Export the database components with our custom implementation
module.exports = {
    sequelize,
    Device: {
        findAll: async () => {
            const devices = dbAdapter.execute('SELECT * FROM Devices');
            // Convert active field from INTEGER to BOOLEAN
            return devices.map(d => ({
                ...d,
                active: d.active === 1
            }));
        },
        findByPk: async (id) => {
            const devices = dbAdapter.execute('SELECT * FROM Devices WHERE id = ?', [id]);
            if (devices.length === 0) return null;
            // Convert active field from INTEGER to BOOLEAN
            return {
                ...devices[0],
                active: devices[0].active === 1,
                update: async (data) => {
                    const now = new Date().toISOString();
                    const activeValue = data.active ? 1 : 0;
                    dbAdapter.execute(
                        `UPDATE Devices
                         SET name = ?, type = ?, host = ?, port = ?, description = ?, active = ?, updatedAt = ?
                         WHERE id = ?`,
                        [data.name, data.type, data.host, data.port, data.description, activeValue, now, id]
                    );
                    return {
                        ...data,
                        id,
                        createdAt: devices[0].createdAt,
                        updatedAt: now
                    };
                },
                destroy: async () => {
                    dbAdapter.execute('DELETE FROM Devices WHERE id = ?', [id]);
                    return true;
                }
            };
        },
        count: async () => {
            const result = dbAdapter.execute('SELECT COUNT(*) as count FROM Devices');
            return result[0].count;
        },
        create: async (data) => {
            const now = new Date().toISOString();
            const activeValue = data.active ? 1 : 0;
            const result = dbAdapter.execute(
                `INSERT INTO Devices (name, type, host, port, description, active, createdAt, updatedAt)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                [data.name, data.type, data.host, data.port, data.description, activeValue, now, now]
            );
            return {
                ...data,
                id: result.lastInsertRowid,
                createdAt: now,
                updatedAt: now
            };
        }
    },
    initDatabase,
    DataTypes // Export DataTypes for use in model definitions
};