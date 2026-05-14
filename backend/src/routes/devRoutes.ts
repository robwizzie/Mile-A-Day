import { Router } from 'express';
import {
	generateTestToken,
	triggerCompetitionCron,
	sendTestNotification,
	triggerSilentSyncFanout,
	triggerSilentSyncForUser
} from '../controllers/devController.js';

const router = Router();

router.post('/test-token', generateTestToken);
router.post('/run-competition-cron', triggerCompetitionCron);
router.post('/test-notification', sendTestNotification);
router.post('/silent-sync-fanout', triggerSilentSyncFanout);
router.post('/silent-sync/:userId', triggerSilentSyncForUser);

export default router;
