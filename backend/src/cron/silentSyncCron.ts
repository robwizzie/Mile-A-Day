import cron from 'node-cron';
import { PostgresService } from '../services/DbService.js';
import { sendSilentPushToUser } from '../services/pushNotificationService.js';

const db = PostgresService.getInstance();

/**
 * Trigger the background-sync silent push for every user with a registered device token.
 * Exported so dev routes can invoke it on-demand.
 */
export async function runSilentSyncPushFanout(): Promise<{ users: number; pushes: number }> {
	const rows = await db.query<{ user_id: string }>(`SELECT DISTINCT user_id FROM device_tokens`);

	let pushes = 0;
	for (const { user_id } of rows) {
		try {
			pushes += await sendSilentPushToUser(user_id, 'background_sync');
		} catch (err: any) {
			console.error(`[SilentSyncCron] Error pushing user ${user_id}:`, err.message);
		}
	}

	return { users: rows.length, pushes };
}

export function startSilentSyncCron(): void {
	// 8am, 12pm, 4pm, 8pm, and 11:45pm ET. The 11:45pm run flushes late-evening
	// workouts before midnight competition resolution / end-of-day tie checks.
	cron.schedule(
		'0 8,12,16,20 * * *',
		async () => {
			console.log('[CRON] Silent sync push fanout starting...');
			try {
				const { users, pushes } = await runSilentSyncPushFanout();
				console.log(`[CRON] Silent sync push fanout complete: ${users} users, ${pushes} pushes`);
			} catch (err: any) {
				console.error('[CRON] Silent sync push fanout failed:', err.message);
			}
		},
		{ timezone: 'America/New_York' }
	);

	cron.schedule(
		'45 23 * * *',
		async () => {
			console.log('[CRON] Pre-midnight silent sync push fanout starting...');
			try {
				const { users, pushes } = await runSilentSyncPushFanout();
				console.log(`[CRON] Pre-midnight silent sync fanout complete: ${users} users, ${pushes} pushes`);
			} catch (err: any) {
				console.error('[CRON] Pre-midnight silent sync fanout failed:', err.message);
			}
		},
		{ timezone: 'America/New_York' }
	);

	console.log('Silent sync push cron scheduled (8am, 12pm, 4pm, 8pm, 11:45pm ET).');
}
