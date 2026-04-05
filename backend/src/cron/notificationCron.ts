import cron from 'node-cron';
import { flushBatchedNotifications } from '../services/pushNotificationService.js';
import { checkCompetitionsEndingSoon } from '../services/notificationService.js';

export function startNotificationCron(): void {
	// Flush batched competition start/finish notifications at 10 AM ET
	cron.schedule('0 10 * * *', async () => {
		console.log('[CRON] Flushing batched notifications...');
		try {
			await flushBatchedNotifications();
			console.log('[CRON] Batched notification flush complete.');
		} catch (error: any) {
			console.error('[CRON] Error flushing notifications:', error.message);
		}
	}, {
		timezone: 'America/New_York'
	});

	// Check for competitions ending tomorrow at 6 PM ET
	cron.schedule('0 18 * * *', async () => {
		console.log('[CRON] Checking competitions ending soon...');
		try {
			await checkCompetitionsEndingSoon();
			console.log('[CRON] Ending soon check complete.');
		} catch (error: any) {
			console.error('[CRON] Error checking ending soon:', error.message);
		}
	}, {
		timezone: 'America/New_York'
	});

	console.log('Notification cron jobs scheduled (10 AM & 6 PM ET).');
}
