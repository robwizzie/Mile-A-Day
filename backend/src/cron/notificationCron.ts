import cron from 'node-cron';
import { flushBatchedNotifications, cleanupNotificationLogs } from '../services/pushNotificationService.js';
import {
	checkCompetitionsEndingSoon,
	checkStreaksBroken,
	checkStreakLifeLoss,
	checkTargetMissed,
	notifyIntervalResults,
	checkClashTies
} from '../services/notificationService.js';
import { sendPendingDailyReminders } from '../services/dailyReminderService.js';
import { expireStalePendingNotifications } from '../services/pendingNotificationService.js';

export function startNotificationCron(): void {
	// All "overnight result" notifications fire together at 9 AM ET so users
	// aren't woken at midnight. This covers:
	//   - flushBatchedNotifications: drains competition_finished pushes queued
	//     by the midnight resolveExpiredCompetitions job (via
	//     sendOrQueueCompetitionNotification's quiet-hours queue)
	//   - checkClashTies: end-of-day tie detection (was midnight)
	//   - checkStreaksBroken + checkStreakLifeLoss + checkTargetMissed: yesterday-
	//     was-a-miss notifications (was 12:05 AM)
	//   - notifyIntervalResults: yesterday-recap digest (was 12:10 AM)
	//
	// Order: tie/streak/target/recap pushes are sent directly (not queued),
	// so we run flushBatchedNotifications first to clear the midnight queue,
	// then the result-detection jobs in the same order they ran overnight.
	// User-triggered notifications (mile finished, nudges, flexes, hypes) are
	// unchanged and continue to send immediately.
	cron.schedule(
		'0 9 * * *',
		async () => {
			console.log('[CRON] 9 AM overnight notification batch starting...');
			try {
				await flushBatchedNotifications();
				console.log('[CRON] Batched notification flush complete.');
			} catch (error: any) {
				console.error('[CRON] Error flushing notifications:', error.message);
			}
			try {
				await checkClashTies();
				console.log('[CRON] Clash tie check complete.');
			} catch (error: any) {
				console.error('[CRON] Error checking clash ties:', error.message);
			}
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

		// Expire stale pending-friend-notification rows (ask-mode). Lazy expiry on
		// read already guarantees correctness; this is hygiene to keep the table tidy.
		try {
			await expireStalePendingNotifications();
		} catch (error: any) {
			console.error('[CRON] Error expiring stale pending notifications:', error.message);
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

	console.log('Notification cron jobs scheduled (hourly daily-reminder + 3 AM, 9 AM, 6 PM ET).');
}
