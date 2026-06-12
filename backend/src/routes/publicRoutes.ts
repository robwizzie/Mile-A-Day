import { Router } from 'express';
import { getPublicUserCount } from '../controllers/usersController.js';

const router = Router();

// Public routes — mounted before authenticateToken. CORS open so the
// marketing site (mileaday.run) can fetch directly from the browser.
router.use((_req, res, next) => {
	res.setHeader('Access-Control-Allow-Origin', '*');
	next();
});

router.get('/user-count', getPublicUserCount);

export default router;
