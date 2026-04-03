import { Router } from 'express';
import { generateTestToken, triggerCompetitionCron, sendTestNotification } from '../controllers/devController.js';

const router = Router();

router.post('/test-token', generateTestToken);
router.post('/run-competition-cron', triggerCompetitionCron);
router.post('/test-notification', sendTestNotification);

export default router;
