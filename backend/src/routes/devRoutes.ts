import { Router } from 'express';
import { generateTestToken, triggerCompetitionCron } from '../controllers/devController.js';

const router = Router();

router.post('/test-token', generateTestToken);
router.post('/run-competition-cron', triggerCompetitionCron);

export default router;
