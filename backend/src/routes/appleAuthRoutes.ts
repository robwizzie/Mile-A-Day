import { Router } from 'express';
import { authenticateWithApple, verifyToken } from '../controllers/appleAuthController.js';

const router = Router();

router.post('/authenticate', authenticateWithApple);
router.post('/verify', verifyToken);

export default router;
