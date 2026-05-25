import cron from 'node-cron';
import { flushBatchedNotifications, cleanupNotificationLogs } from '../services/pushNotificationService.js';
import {
	checkCompetitionsEndingSoon,
	checkStreaksBroken,
	checkClashTies,
	checkStreakLifeLoss,
	checkTargetMissed,
	notifyIntervalResults
} from '../services/notificationService.js';
import { sendPendingDailyReminders } from '../services/dailyReminderService.js';

export function startNotificationCron(): void {
	// Flush batched competition start/finish notifications at 10 AM ET
	cron.schedule(
		'0 10 * * *',
		async () => {
			console.log('[CRON] Flushing batched notifications...');
			try {
				await flushBatchedNotifications();
				console.log('[CRON] Batched notification flush complete.');
			} catch (error: any) {
				console.error('[CRON] Error flushing notifications:', error.message);
			}
		},
		{
			timezone: 'America/New_York'
		}
	);

	// Check for competitions ending tomorrow at 6 PM ET
	cron.schedule(
		'0 18 * * *',
		async () => {
			console.log('[CRON] Checking competitions ending soon...');
			try {
				await checkCompetitionsEndingSoon();
				console.log('[CRON] Ending soon check complete.');
			} catch (error: any) {
				console.error('[CRON] Error checking ending soon:', error.message);
			}
		},
		{
			timezone: 'America/New_York'
		}
	);

	// Check for broken streaks at 12:05 AM ET (after midnight competition resolution).
	// In the same slot we also run the competition-streak life-loss check and the
	// targets-missed check, which all share the "just rolled over to a new day" trigger.
	cron.schedule(
		'5 0 * * *',
		async () => {
			console.log('[CRON] Checking for broken streaks + competition life/target loss...');
			try {
				await checkStreaksBroken();
				console.log('[CRON] Personal streak broken check complete.');
			} catch (error: any) {
				console.error('[CRON] Error checking broken streaks:', error.message);
			}
			try {
				await checkStreakLifeLoss();
				console.log('[CRON] Competition streak life-loss check complete.');
			} catch (error: any) {
				console.error('[CRON] Error checking streak life loss:', error.message);
			}
			try {
				await checkTargetMissed();
				console.log('[CRON] Target-missed check complete.');
			} catch (error: any) {
				console.error('[CRON] Error checking target missed:', error.message);
			}
		},
		{
			timezone: 'America/New_York'
		}
	);

	// Interval recap: fires 5 minutes after the life/target jobs so the
	// individual misses-and-life-losses arrive first and the recap reads as
	// a single "see how everyone finished" follow-up. Groups across all of
	// a user's comps so heavy users don't get flooded.
	cron.schedule(
		'10 0 * * *',
		async () => {
			console.log('[CRON] Sending interval recap notifications...');
			try {
				await notifyIntervalResults();
				console.log('[CRON] Interval recap complete.');
			} catch (error: any) {
				console.error('[CRON] Error sending interval recap:', error.message);
			}
		},
		{
			timezone: 'America/New_York'
		}
	);

	// Check for clash ties at 11:55 PM ET (end of day)
	cron.schedule(
		'55 23 * * *',
		async () => {
			console.log('[CRON] Checking for clash ties...');
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

	// Every hour at :00 — fire daily "mile still waiting" reminders to users whose
	// current local hour matches their configured reminder hour and who haven't
	// completed today's mile. Per-user TZ filtering is in the SQL.
	cron.schedule('0 * * * *', async () => {
		console.log('[CRON] Sending pending daily reminders...');
		try {
			await sendPendingDailyReminders();
			console.log('[CRON] Daily reminder send complete.');
		} catch (error: any) {
			console.error('[CRON] Error sending daily reminders:', error.message);
		}
	});

	// Clean up old notification logs at 3 AM ET daily
	cron.schedule(
		'0 3 * * *',
		async () => {
			console.log('[CRON] Cleaning up old notification logs...');
			try {
				await cleanupNotificationLogs();
				console.log('[CRON] Notification log cleanup complete.');
			} catch (error: any) {
				console.error('[CRON] Error cleaning up logs:', error.message);
			}
		},
		{
			timezone: 'America/New_York'
		}
	);

	console.log('Notification cron jobs scheduled (hourly daily-reminder + 12:05 AM, 3 AM, 10 AM, 6 PM, 11:55 PM ET).');
}
