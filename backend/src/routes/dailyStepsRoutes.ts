import { Router } from 'express';
import { putDailySteps } from '../controllers/dailyStepsController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

router.put('/:userId/daily-steps', requireSelfAccess('userId'), putDailySteps);

export default router;
