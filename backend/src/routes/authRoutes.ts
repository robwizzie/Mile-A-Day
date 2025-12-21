import { Router } from 'express';
import { signIn, refresh, logout, logoutAll } from '../controllers/authController.js';
import { authenticateToken } from '../middleware/auth.js';

const router = Router();

router.post('/signin', signIn);
router.post('/refresh', refresh);
router.post('/logout', logout);
router.post('/logout-all', authenticateToken, logoutAll);

export default router;
