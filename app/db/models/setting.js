// Simple key/value settings store for auth and other per-Pi state.
// Backed by a Settings table in SQLite, used alongside the custom adapter
// in db/index.js. Exported as a thin interface so callers can:
//
//   await Setting.get('local_password_hash')
//   await Setting.set('local_password_hash', '$2b$12$...')
//   await Setting.unset('local_password_hash')

module.exports = (dbAdapter) => ({
    async get(key) {
        const rows = dbAdapter.isAsync()
            ? await dbAdapter.execute('SELECT value FROM Settings WHERE key = ?', [key])
            : dbAdapter.execute('SELECT value FROM Settings WHERE key = ?', [key]);
        return rows.length ? rows[0].value : null;
    },

    async set(key, value) {
        const now = new Date().toISOString();
        const sql = `INSERT INTO Settings (key, value, updatedAt) VALUES (?, ?, ?)
                     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt`;
        if (dbAdapter.isAsync()) {
            await dbAdapter.execute(sql, [key, value, now]);
        } else {
            dbAdapter.execute(sql, [key, value, now]);
        }
    },

    async unset(key) {
        if (dbAdapter.isAsync()) {
            await dbAdapter.execute('DELETE FROM Settings WHERE key = ?', [key]);
        } else {
            dbAdapter.execute('DELETE FROM Settings WHERE key = ?', [key]);
        }
    },
});
