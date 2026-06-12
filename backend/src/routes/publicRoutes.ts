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
// Streaks are public only for allowlisted usernames (see PUBLIC_STREAK_USERNAMES)
router.get('/streak/:username', getPublicUserStreak);

export default router;
