const { PROTECTED_ROUTES } = require('../config/auth');

const AUTH_ENABLED = process.env.AUTH_ENABLED === 'true';

// Middleware that gates protected routes behind session auth when AUTH_ENABLED.
// When disabled, it's a pass-through so existing deployments keep working.
function requireAuth(req, res, next) {
    if (!AUTH_ENABLED) return next();

    const isProtected = PROTECTED_ROUTES.some(
        (r) => r.method === req.method && r.path.test(req.path)
    );
    if (!isProtected) return next();

    if (req.session && req.session.userId) return next();

    return res.status(401).json({ error: 'Authentication required' });
}

module.exports = { requireAuth, AUTH_ENABLED };
