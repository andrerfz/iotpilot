function calculateLRC(data, start, end) {
    let lrc = 0;
    for (let i = start; i < end; i++) {
        lrc ^= data[i];
    }
    return lrc.toString(16).padStart(2, '0').toUpperCase();
}

function formatPresetTareValue(value) {
    // Convert kg to grams (XXXXXX.XX format, grams)
    const grams = Math.round(parseFloat(value) * 1000);
    if (isNaN(grams) || grams < 0 || grams > 30000) {
        throw new Error('Value must be between 0.0 and 30.0 kg');
    }
    // Format as 8-digit ASCII (e.g., 1.0kg -> "00010000")
    return grams.toString().padStart(8, '0');
}

function createPresetTareCmd(value) {
    const formattedValue = formatPresetTareValue(value);
    const presetTareCmd = Buffer.from(`023030464657303130383038${formattedValue}03`, 'ascii');
    return Buffer.concat([presetTareCmd, Buffer.from([0x0D, 0x0A])]);
}

// Scale commands
const weightCmd = Buffer.from([0x02, 0x30, 0x30, 0x46, 0x46, 0x52, 0x30, 0x31, 0x30, 0x37, 0x30, 0x30, 0x30, 0x30, 0x03, 0x0D, 0x0A]);
const tareCmd = Buffer.from([0x02, 0x30, 0x30, 0x46, 0x46, 0x45, 0x31, 0x31, 0x30, 0x33, 0x30, 0x30, 0x30, 0x30, 0x03, 0x0D, 0x0A]);
const statusCmd = Buffer.from([0x02, 0x30, 0x30, 0x46, 0x46, 0x52, 0x30, 0x31, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x03, 0x0D, 0x0A]);
const clearPresetTareCmd = Buffer.from([0x02, 0x30, 0x30, 0x46, 0x46, 0x57, 0x30, 0x31, 0x30, 0x38, 0x30, 0x38, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x03, 0x0D, 0x0A]);

module.exports = {
    weightCmd,
    tareCmd,
    statusCmd,
    clearPresetTareCmd,
    createPresetTareCmd,
    calculateLRC,
};