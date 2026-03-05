import cron from 'node-cron';
import { resolveExpiredCompetitions } from '../services/competitionService.js';

export function startCompetitionCron(): void {
	cron.schedule('0 0 * * *', async () => {
		console.log('[CRON] Running competition resolution...');
		try {
			await resolveExpiredCompetitions();
			console.log('[CRON] Competition resolution complete.');
		} catch (error: any) {
			console.error('[CRON] Error resolving competitions:', error.message);
		}
	}, {
		timezone: 'America/New_York'
	});

	console.log('Competition cron job scheduled (midnight ET).');
}
