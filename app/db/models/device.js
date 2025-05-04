const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
    const Device = sequelize.define('Device', {
        id: {
            type: DataTypes.INTEGER,
            primaryKey: true,
            autoIncrement: true,
        },
        name: {
            type: DataTypes.STRING,
            allowNull: false,
            unique: true,
        },
        type: {
            type: DataTypes.STRING,
            allowNull: false,
            defaultValue: 'scale',
        },
        host: {
            type: DataTypes.STRING,
            allowNull: false,
        },
        port: {
            type: DataTypes.INTEGER,
            allowNull: false,
        },
        description: {
            type: DataTypes.TEXT,
            allowNull: true,
        },
        active: {
            type: DataTypes.BOOLEAN,
            defaultValue: true,
        }
    });

    return Device;
};