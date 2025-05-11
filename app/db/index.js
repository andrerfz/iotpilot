const path = require('path');
const fs = require('fs');
const { DataTypes } = require('sequelize');

// Cross-platform SQLite Adapter that automatically chooses the best available driver
class SQLiteAdapter {
    constructor() {
        this.db = null;
        this.connected = false;
        this.type = 'none';

        // Try to load better-sqlite3 first (faster)
        try {
            this.better = require('better-sqlite3');
            this.type = 'better-sqlite3';
            console.log('Using better-sqlite3 adapter');
        } catch (error) {
            console.log('better-sqlite3 not available, trying sqlite3...');
            // If that fails, try sqlite3
            try {
                this.sqlite3 = require('sqlite3').verbose();
                this.type = 'sqlite3';
                console.log('Using sqlite3 adapter');
            } catch (error) {
                console.error('No SQLite adapter available:', error.message);
                this.type = 'none';
            }
        }
    }

    connect(dbPath) {
        try {
            if (this.type === 'better-sqlite3') {
                try {
                    this.db = new this.better(dbPath, {
                        verbose: process.env.NODE_ENV === 'development' ? console.log : null,
                        fileMustExist: false
                    });

                    // Test the connection
                    this.db.prepare('SELECT 1').get();
                    this.connected = true;
                    return true;
                } catch (err) {
                    console.error('better-sqlite3 connection error:', err.message);
                    this.type = 'sqlite3'; // Fallback to sqlite3
                    return this.connect(dbPath); // Try connecting with sqlite3
                }
            } else if (this.type === 'sqlite3') {
                return new Promise((resolve) => {
                    this.db = new this.sqlite3.Database(dbPath, (err) => {
                        if (err) {
                            console.error('sqlite3 connection error:', err.message);
                            this.connected = false;
                            resolve(false);
                        } else {
                            this.connected = true;
                            resolve(true);
                        }
                    });
                });
            } else {
                console.error('No SQLite adapter available');
                this.connected = false;
                return false;
            }
        } catch (error) {
            console.error('Database connection error:', error.message);
            this.connected = false;
            return false;
        }
    }

    close() {
        if (this.db) {
            if (this.type === 'better-sqlite3') {
                this.db.close();
            } else if (this.type === 'sqlite3') {
                this.db.close();
            }
            this.db = null;
            this.connected = false;
        }
    }

    execute(sql, params = []) {
        try {
            if (!this.db) {
                throw new Error('Database not connected');
            }

            if (this.type === 'better-sqlite3') {
                // better-sqlite3 implementation
                if (sql.trim().toUpperCase().startsWith('SELECT')) {
                    const stmt = this.db.prepare(sql);
                    return stmt.all(...params);
                } else {
                    const stmt = this.db.prepare(sql);
                    return stmt.run(...params);
                }
            } else if (this.type === 'sqlite3') {
                // sqlite3 implementation
                return new Promise((resolve, reject) => {
                    if (sql.trim().toUpperCase().startsWith('SELECT')) {
                        this.db.all(sql, params, (err, rows) => {
                            if (err) {
                                console.error('SQL execution error:', err.message);
                                reject(err);
                            } else {
                                resolve(rows);
                            }
                        });
                    } else {
                        this.db.run(sql, params, function(err) {
                            if (err) {
                                console.error('SQL execution error:', err.message);
                                reject(err);
                            } else {
                                resolve({
                                    lastInsertRowid: this.lastID,
                                    changes: this.changes
                                });
                            }
                        });
                    }
                });
            } else {
                throw new Error('No SQLite adapter available');
            }
        } catch (error) {
            console.error('SQL execution error:', error.message);
            throw error;
        }
    }

    // Add a method to check if we're using the asynchronous API
    isAsync() {
        return this.type === 'sqlite3';
    }
}

// Create the database file in the app directory for persistence
const dataDir = path.join(__dirname, '..', 'data');
const dbPath = path.join(dataDir, 'iotpilot.sqlite');
let dbAdapter = new SQLiteAdapter();
let inMemoryMode = false;

// Generate a dummy sequelize instance for compatibility
// This MUST be defined before using it in deviceModel below
const sequelize = {
    define: (modelName, attributes, options) => {
        console.log(`Mock Sequelize: Defined model ${modelName}`);
        return {};
    }
};

// NOW we can use the sequelize variable
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
        let connected = false;

        if (dbAdapter.isAsync()) {
            connected = await dbAdapter.connect(dbPath);
        } else {
            connected = dbAdapter.connect(dbPath);
        }

        if (!connected) {
            console.warn('Using in-memory database mode');
            inMemoryMode = true;
            // Set up in-memory tables
            if (dbAdapter.isAsync()) {
                await dbAdapter.connect(':memory:');
            } else {
                dbAdapter.connect(':memory:');
            }
        }

        // Create tables if they don't exist
        const createTableSql = `
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
        `;

        if (dbAdapter.isAsync()) {
            await dbAdapter.execute(createTableSql);
        } else {
            dbAdapter.execute(createTableSql);
        }

        console.log('Database initialized successfully');

        // Check if we have any devices, if not add a default one
        if (!defaultDeviceCreated) {
            let devices;
            if (dbAdapter.isAsync()) {
                devices = await dbAdapter.execute('SELECT COUNT(*) as count FROM Devices');
            } else {
                devices = dbAdapter.execute('SELECT COUNT(*) as count FROM Devices');
            }

            if (devices[0].count === 0) {
                // Add default device
                const now = new Date().toISOString();
                if (dbAdapter.isAsync()) {
                    await dbAdapter.execute(
                        `INSERT INTO Devices (name, type, host, port, description, active, createdAt, updatedAt)
                         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                        ['Default Scale', 'scale', '192.168.1.11', 9999,
                            inMemoryMode ? 'Default HF2211 scale device (in-memory, will be lost on restart)' : 'Default HF2211 scale device',
                            1, now, now]
                    );
                } else {
                    dbAdapter.execute(
                        `INSERT INTO Devices (name, type, host, port, description, active, createdAt, updatedAt)
                         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                        ['Default Scale', 'scale', '192.168.1.11', 9999,
                            inMemoryMode ? 'Default HF2211 scale device (in-memory, will be lost on restart)' : 'Default HF2211 scale device',
                            1, now, now]
                    );
                }
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

// Modified Device model with async handling
const DeviceModel = {
    findAll: async () => {
        if (dbAdapter.isAsync()) {
            const devices = await dbAdapter.execute('SELECT * FROM Devices');
            // Convert active field from INTEGER to BOOLEAN
            return devices.map(d => ({
                ...d,
                active: d.active === 1
            }));
        } else {
            const devices = dbAdapter.execute('SELECT * FROM Devices');
            // Convert active field from INTEGER to BOOLEAN
            return devices.map(d => ({
                ...d,
                active: d.active === 1
            }));
        }
    },

    findByPk: async (id) => {
        let devices;
        if (dbAdapter.isAsync()) {
            devices = await dbAdapter.execute('SELECT * FROM Devices WHERE id = ?', [id]);
        } else {
            devices = dbAdapter.execute('SELECT * FROM Devices WHERE id = ?', [id]);
        }

        if (devices.length === 0) return null;

        // Convert active field from INTEGER to BOOLEAN
        return {
            ...devices[0],
            active: devices[0].active === 1,
            update: async (data) => {
                const now = new Date().toISOString();
                const activeValue = data.active ? 1 : 0;

                if (dbAdapter.isAsync()) {
                    await dbAdapter.execute(
                        `UPDATE Devices
                         SET name = ?, type = ?, host = ?, port = ?, description = ?, active = ?, updatedAt = ?
                         WHERE id = ?`,
                        [data.name, data.type, data.host, data.port, data.description, activeValue, now, id]
                    );
                } else {
                    dbAdapter.execute(
                        `UPDATE Devices
                         SET name = ?, type = ?, host = ?, port = ?, description = ?, active = ?, updatedAt = ?
                         WHERE id = ?`,
                        [data.name, data.type, data.host, data.port, data.description, activeValue, now, id]
                    );
                }

                return {
                    ...data,
                    id,
                    createdAt: devices[0].createdAt,
                    updatedAt: now
                };
            },
            destroy: async () => {
                if (dbAdapter.isAsync()) {
                    await dbAdapter.execute('DELETE FROM Devices WHERE id = ?', [id]);
                } else {
                    dbAdapter.execute('DELETE FROM Devices WHERE id = ?', [id]);
                }
                return true;
            }
        };
    },

    count: async () => {
        let result;
        if (dbAdapter.isAsync()) {
            result = await dbAdapter.execute('SELECT COUNT(*) as count FROM Devices');
        } else {
            result = dbAdapter.execute('SELECT COUNT(*) as count FROM Devices');
        }
        return result[0].count;
    },

    create: async (data) => {
        const now = new Date().toISOString();
        const activeValue = data.active ? 1 : 0;
        let result;

        if (dbAdapter.isAsync()) {
            result = await dbAdapter.execute(
                `INSERT INTO Devices (name, type, host, port, description, active, createdAt, updatedAt)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                [data.name, data.type, data.host, data.port, data.description, activeValue, now, now]
            );
        } else {
            result = dbAdapter.execute(
                `INSERT INTO Devices (name, type, host, port, description, active, createdAt, updatedAt)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                [data.name, data.type, data.host, data.port, data.description, activeValue, now, now]
            );
        }

        const id = dbAdapter.isAsync() ? result.lastID : result.lastInsertRowid;

        return {
            ...data,
            id,
            createdAt: now,
            updatedAt: now
        };
    }
};

// Export the database components with our custom implementation
module.exports = {
    sequelize,
    Device: DeviceModel,
    initDatabase,
    DataTypes // Export DataTypes for use in model definitions
};