/**
 * scaleParser.js
 * Module dedicated to parsing scale responses for different command types.
 * This module handles specialized parsing for HF2211 scale protocol responses.
 */

const scaleCommands = require('./scaleCommands');

// Status code descriptions for easier reference
const STATUS_CODE_DESCRIPTIONS = {
    0x00: 'No error',
    0x01: 'Error reading configuration from flash',
    0x02: 'A/D converter failure',
    0x03: 'Load cell signal out of range',
    0x04: 'Load cell signal > 30mV',
    0x05: 'Load cell signal < -30mV',
    0x06: 'Load cell power supply failure',
    0x07: 'Overload (> Max + 9e)',
    0x08: 'Negative weight (< -19e)',
    0x40: 'Calibration or mode warning (firmware-specific)'
};

/**
 * Parse a raw response from the scale based on the command type
 * @param {Buffer} data - The raw data received from the scale
 * @param {Buffer} command - The command that was sent to the scale
 * @param {string} rawResponse - Hex string of the raw response for error reporting
 * @returns {object} Parsed response object with appropriate fields
 */
function parseResponse(data, command, rawResponse = '') {
    let responseData = {};

    // Try to detect the response type and parse accordingly
    if (data.length >= 43 && data[5] === 0x72 && data.slice(6, 10).toString('ascii') === '0107') {
        responseData = parseWeightResponse(data);
    }
    else if (data.length >= 16 && data[5] === 0x72 && data.slice(6, 10).toString('ascii') === '0100') {
        responseData = parseStatusResponse(data);
    }
    else if (Buffer.compare(command, scaleCommands.tareCmd) === 0 && data.length >= 16) {
        responseData = parseTareResponse(data, command);
    }
    else if ((Buffer.compare(command, scaleCommands.clearPresetTareCmd) === 0 ||
            (command.length > 12 && command.slice(5, 13).toString('ascii') === 'W010808'))
        && data.length >= 16 && data[5] === 0x77) {
        responseData = parsePresetTareResponse(data, command);
    }
    else {
        responseData.type = 'error';
        responseData.error = 'Invalid or unrecognized response';
        responseData.rawResponse = rawResponse;
    }

    return responseData;
}

/**
 * Parse a weight response from the scale
 * @param {Buffer} data - The raw data received from the scale
 * @returns {object} Parsed weight response
 */
function parseWeightResponse(data) {
    const responseData = {
        type: 'weight',
        unit: 'kg',
    };

    // Extract the weight data fields
    responseData.gross = data.slice(12, 23).toString('ascii');
    responseData.tare = data.slice(23, 34).toString('ascii');
    responseData.flags = data.slice(34, 38).toString('ascii');
    responseData.lrc = data.slice(38, 40).toString('ascii');

    // Validate LRC checksum
    const computedLRC = scaleCommands.calculateLRC(data, 1, 38);
    responseData.lrcValid = computedLRC === responseData.lrc;
    console.log(`Weight LRC: computed=${computedLRC}, received=${responseData.lrc}`);

    // Calculate net weight
    const grossVal = parseFloat(responseData.gross.replace('W', '').trim());
    const tareVal = parseFloat(responseData.tare.replace('T', '').trim());
    responseData.weight = isNaN(grossVal) || isNaN(tareVal) ? null : grossVal - tareVal;

    // Parse status flags
    const flagsValue = parseInt(responseData.flags.slice(1), 16);
    responseData.statusFlags = parseStatusFlags(flagsValue);

    return responseData;
}

/**
 * Parse the status flags value from a weight response
 * @param {number} flagsValue - The numeric value of the status flags
 * @returns {object} Object containing parsed status flags
 */
function parseStatusFlags(flagsValue) {
    return {
        zero: (flagsValue & 0x001) > 0,
        tare: (flagsValue & 0x002) > 0,
        stable: (flagsValue & 0x004) > 0,
        net: (flagsValue & 0x008) > 0,
        tareMode: (flagsValue & 0x010) > 0 ? 'preset' : 'normal',
        highResolution: (flagsValue & 0x020) > 0,
        initialZero: (flagsValue & 0x040) > 0,
        overload: (flagsValue & 0x080) > 0,
        negative: (flagsValue & 0x100) > 0,
        range: (flagsValue & 0x200) > 0 ? 2 : 1,
        presetTare: (flagsValue & 0x400) > 0
    };
}

/**
 * Parse a status response from the scale
 * @param {Buffer} data - The raw data received from the scale
 * @returns {object} Parsed status response
 */
function parseStatusResponse(data) {
    const responseData = {
        type: 'status'
    };

    const dataLength = parseInt(data.slice(10, 12).toString('ascii'), 16);

    if (data.length >= 12 + dataLength + 3) {
        const statusCode = parseInt(data.slice(12, 12 + dataLength).toString('ascii'), 16);
        responseData.status = {
            code: statusCode,
            description: STATUS_CODE_DESCRIPTIONS[statusCode] || 'Unknown'
        };

        responseData.lrc = data.slice(12 + dataLength, 14 + dataLength).toString('ascii');
        const computedLRC = scaleCommands.calculateLRC(data, 1, 12 + dataLength);
        responseData.lrcValid = computedLRC === responseData.lrc;
        console.log(`Status LRC: computed=${computedLRC}, received=${responseData.lrc}`);
    } else {
        responseData.type = 'error';
        responseData.error = 'Incomplete status response';
    }

    return responseData;
}

/**
 * Parse a tare command response
 * @param {Buffer} data - The raw data received from the scale
 * @param {Buffer} command - The command that was sent to the scale
 * @returns {object} Parsed tare response
 */
function parseTareResponse(data, command) {
    const responseData = {
        type: 'tare'
    };

    const functionCode = data[5] === 0x65 ? 'execute' : data[5] === 0x77 ? 'write' : 'unknown';

    if (data[5] === 0x65 && data.slice(6, 10).toString('ascii') === '1103') {
        const resultCode = data.slice(12, 13).toString('ascii');
        responseData.message = resultCode === '0' ? 'tare executed successfully' :
            resultCode === '1' ? 'tare failed: Sealing switch locked' :
                `tare failed: Error code ${resultCode}`;

        responseData.lrc = data.slice(13, 15).toString('ascii');
        const computedLRC = scaleCommands.calculateLRC(data, 1, 13);
        responseData.lrcValid = computedLRC === responseData.lrc;
        console.log(`Tare LRC: computed=${computedLRC}, received=${responseData.lrc}`);

        // Return success status
        responseData.success = resultCode === '0';
    } else {
        responseData.type = 'error';
        responseData.error = `Unexpected response: function=${functionCode}, address=${data.slice(6, 10).toString('ascii')}`;
    }

    return responseData;
}

/**
 * Parse a preset tare command response
 * @param {Buffer} data - The raw data received from the scale
 * @param {Buffer} command - The command that was sent to the scale
 * @returns {object} Parsed preset tare response
 */
function parsePresetTareResponse(data, command) {
    const responseType = Buffer.compare(command, scaleCommands.clearPresetTareCmd) === 0 ? 'clearPreset' : 'presetTare';

    const responseData = {
        type: responseType
    };

    const resultCode = data.slice(12, 13).toString('ascii');
    responseData.message = resultCode === '0' ?
        `${responseType === 'clearPreset' ? 'Preset tare cleared' : 'Preset tare set'} successfully` :
        resultCode === '1' ?
            `${responseType} failed: Sealing switch locked` :
            resultCode === '5' ?
                `${responseType} already set/clear or firmware quirk` :
                `${responseType} failed: Error code ${resultCode}`;

    responseData.lrc = data.slice(13, 15).toString('ascii');
    const computedLRC = scaleCommands.calculateLRC(data, 1, 13);
    responseData.lrcValid = computedLRC === responseData.lrc;
    console.log(`${responseType} LRC: computed=${computedLRC}, received=${responseData.lrc}`);

    // Return success status
    responseData.success = resultCode === '0';

    return responseData;
}

/**
 * Check if a response is valid based on its structure
 * @param {Buffer} data - The raw data received from the scale
 * @returns {boolean} Whether the response has a valid structure
 */
function isValidResponse(data) {
    // Basic structural checks for scale responses
    if (!data || data.length < 12) {
        return false;
    }

    // Check for STX and ETX markers
    return !(data[0] !== 0x02 || !data.includes(0x03));
}

module.exports = {
    parseResponse,
};