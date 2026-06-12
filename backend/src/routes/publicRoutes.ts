import { Router } from 'express';
import { getPublicUserCount, getPublicUserStreak } from '../controllers/usersController.js';

const router = Router();

// Public routes — mounted before authenticateToken. CORS open so the
// marketing site (mileaday.run) can fetch directly from the browser.
router.use((_req, res, next) => {
	res.setHeader('Access-Control-Allow-Origin', '*');
	next();
});

router.get('/user-count', getPublicUserCount);
// Alias — same count payload. Exposes NO per-user data.
router.get('/users', getPublicUserCount);
// Streaks are public only for allowlisted usernames (see PUBLIC_STREAK_USERNAMES)
router.get('/streak/:username', getPublicUserStreak);

// Unknown /public/* paths should 404 here, not fall through to the auth
// middleware (which confusingly answers "access token required").
router.use((_req, res) => {
	res.status(404).json({ error: 'Not found' });
});

export default router;
