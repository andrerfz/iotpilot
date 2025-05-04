// app/db/index.js
const { Sequelize } = require('sequelize');
const path = require('path');
const fs = require('fs');

// Create the database file in the app directory for persistence
const dataDir = path.join(__dirname, '..', 'data');
const dbPath = path.join(dataDir, 'iotpilot.sqlite');

// Initialize Sequelize with SQLite
const sequelize = new Sequelize({
    dialect: 'sqlite',
    storage: dbPath,
    logging: console.log,
    retry: {
        max: 3
    }
});

// Import models
const Device = require('./models/device')(sequelize);

// Track whether we've already created a default device in this session
let defaultDeviceCreated = false;

// Sync the database
const initDatabase = async () => {
    try {
        // Try to authenticate first
        await sequelize.authenticate();
        console.log('Database connection established successfully');

        // Use alter: false to avoid recreation issues
        await sequelize.sync({ alter: false });
        console.log('Database synchronized successfully');

        // Check if we have any devices, if not add a default one
        // Only do this once per application run to avoid duplicates
        if (!defaultDeviceCreated) {
            const count = await Device.count();
            if (count === 0) {
                await Device.create({
                    name: 'Default Scale',
                    type: 'scale',
                    host: '192.168.1.11',
                    port: 9999,
                    description: 'Default HF2211 scale device'
                });
                console.log('Default device created');
                defaultDeviceCreated = true;
            } else {
                console.log(`Found ${count} existing devices, skipping default device creation`);
            }
        }
    } catch (error) {
        console.error('Error syncing database:', error);

        // If we can't use the file-based database, fall back to in-memory
        if (error.name === 'SequelizeDatabaseError' &&
            (error.parent?.code === 'SQLITE_READONLY' || error.original?.code === 'SQLITE_READONLY')) {
            console.warn('Warning: Using temporary in-memory database');

            // Create a new in-memory connection
            const memSequelize = new Sequelize('sqlite::memory:', {
                logging: console.log
            });

            // Replace the main sequelize instance for the session
            sequelize.close();
            Object.assign(sequelize, memSequelize);

            // Re-import model with new connection
            const MemDevice = require('./models/device')(sequelize);
            Object.assign(Device, MemDevice);

            // Sync the in-memory database
            await sequelize.sync({ force: true });

            // Only create the default device if we haven't already done so
            if (!defaultDeviceCreated) {
                await Device.create({
                    name: 'Default Scale (Temporary)',
                    type: 'scale',
                    host: '192.168.1.11',
                    port: 9999,
                    description: 'Default HF2211 scale device (in-memory, will be lost on restart)'
                });
                defaultDeviceCreated = true;
                console.log('Created default device in in-memory database');
            }
        }
    }
};

module.exports = {
    sequelize,
    Device,
    initDatabase,
};