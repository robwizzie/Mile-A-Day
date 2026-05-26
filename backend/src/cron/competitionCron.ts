import cron from 'node-cron';
import { resolveExpiredCompetitions } from '../services/competitionService.js';
import { checkClashTies } from '../services/notificationService.js';

export function startCompetitionCron(): void {
	cron.schedule(
		'0 0 * * *',
		async () => {
			console.log('[CRON] Running competition resolution...');
			try {
				await resolveExpiredCompetitions();
				console.log('[CRON] Competition resolution complete.');
			} catch (error: any) {
				console.error('[CRON] Error resolving competitions:', error.message);
			}

			// Run end-of-day tie detection AFTER resolution so scores reflect the
			// just-finished day. Resolved comps self-suppress via the winner check.
			try {
				await checkClashTies();
				console.log('[CRON] Clash tie check complete.');
			} catch (error: any) {
				console.error('[CRON] Error checking clash ties:', error.message);
			}
		},
		{
			timezone: 'America/New_York'
		}
	);

	console.log('Competition cron job scheduled (midnight ET, includes tie check).');
}
