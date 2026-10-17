import { Router } from 'express';
import { putDailySteps, putDailyStepsBatch } from '../controllers/dailyStepsController.js';
import { requireSelfAccess } from '../middleware/auth.js';

const router = Router();

router.put('/:userId/daily-steps', requireSelfAccess('userId'), putDailySteps);
router.put('/:userId/daily-steps/batch', requireSelfAccess('userId'), putDailyStepsBatch);

export default router;
