import { Router } from 'express';
import { getTodayForUser, getCompletionsForUser } from '../controllers/dailyChallengeController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();
router.get('/:userId/challenges/today', getTodayForUser);
router.get('/:userId/challenges', requireSelfAccess('userId'), getCompletionsForUser);

export default router;
