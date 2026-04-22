// Auth configuration.
//
// MASTER_HASH is the bcrypt hash of the global admin password. It is shared
// across all IoTPilot deployments and committed to the public repo. The
// plaintext is intentionally kept out of the codebase and stored only in
// Yurest's password manager.
//
// Security model: the password must have >=128 bits of entropy so bcrypt at
// cost 12 is computationally infeasible to crack even if someone clones the
// repo. To rotate, generate a new hash, replace the constant, push, and run
// `make update-prod` on each Pi.
//
// The local (per-Pi) password hash lives in the Settings table of the SQLite
// database and is managed from the Configuración UI. Either hash can log in.

// Replace before merging feat/auth to main. Until then, this placeholder is
// intentionally non-matchable (a real bcrypt hash begins with $2a$/$2b$/$2y$
// followed by a 22-char base64 salt; the string below is shorter and will
// always fail verification, so nobody can log in via "master" on feat/auth).
const MASTER_HASH = '$2b$12$SET-ME-BEFORE-MERGE-TO-MAIN';

module.exports = {
    MASTER_HASH,
    BCRYPT_COST: 12,
    SESSION_COOKIE_NAME: 'iotpilot.sid',
    // Protected routes: any mutation, scale-writing commands, and import.
    // Read-only endpoints (GET /api/devices, /weight, /status) stay open
    // so the KDS client and other LAN readers keep working.
    PROTECTED_ROUTES: [
        { method: 'POST', path: /^\/api\/devices(\/.*)?$/ },
        { method: 'PUT', path: /^\/api\/devices\/.*/ },
        { method: 'DELETE', path: /^\/api\/devices\/.*/ },
        { method: 'GET', path: /^\/api\/devices\/[^/]+\/tare$/ },
        { method: 'GET', path: /^\/api\/devices\/[^/]+\/clearPreset$/ },
        { method: 'GET', path: /^\/api\/devices\/[^/]+\/presetTare$/ },
    ],
};
