import { Router } from 'express';
import { signIn, refresh, logout, logoutAll } from '../controllers/authController.js';
import { authenticateToken } from '../middleware/auth.js';
import { signInLimiter, sessionLimiter } from '../middleware/rateLimit.js';

const router = Router();

// Separate buckets on purpose: a 429 from /refresh signs a shipped client out,
// so it must never share a count with sign-in attempts (see rateLimit.ts).
router.post('/signin', signInLimiter, signIn);
router.post('/refresh', sessionLimiter, refresh);
router.post('/logout', sessionLimiter, logout);
router.post('/logout-all', authenticateToken, logoutAll);

export default router;
