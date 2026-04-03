import cron from 'node-cron';
import { flushBatchedNotifications } from '../services/pushNotificationService.js';

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

	console.log('Notification cron job scheduled (10 AM ET).');
}
