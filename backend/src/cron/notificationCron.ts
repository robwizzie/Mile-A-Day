import cron from "node-cron";
import {
  flushBatchedNotifications,
  cleanupNotificationLogs,
} from "../services/pushNotificationService.js";
import {
  checkCompetitionsEndingSoon,
  checkStreaksBroken,
  checkStreakLifeLoss,
  checkTargetMissed,
  notifyIntervalResults,
  checkClashTies,
} from "../services/notificationService.js";
import { sendPendingDailyReminders } from "../services/dailyReminderService.js";
import { reconcileStaleStreaks } from "../services/leaderboardService.js";
import { expireStalePendingNotifications } from "../services/pendingNotificationService.js";
import { sendPendingFriendRequestReminders } from "../services/friendRequestReminderService.js";

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
    "0 9 * * *",
    async () => {
      console.log("[CRON] 9 AM overnight notification batch starting...");
      try {
        await flushBatchedNotifications();
        console.log("[CRON] Batched notification flush complete.");
      } catch (error: any) {
        console.error("[CRON] Error flushing notifications:", error.message);
      }
      try {
        await checkClashTies();
        console.log("[CRON] Clash tie check complete.");
      } catch (error: any) {
        console.error("[CRON] Error checking clash ties:", error.message);
      }
      try {
        await checkStreaksBroken();
        console.log("[CRON] Personal streak broken check complete.");
      } catch (error: any) {
        console.error("[CRON] Error checking broken streaks:", error.message);
      }
      try {
        await checkStreakLifeLoss();
        console.log("[CRON] Competition streak life-loss check complete.");
      } catch (error: any) {
        console.error("[CRON] Error checking streak life loss:", error.message);
      }
      try {
        await checkTargetMissed();
        console.log("[CRON] Target-missed check complete.");
      } catch (error: any) {
        console.error("[CRON] Error checking target missed:", error.message);
      }
      try {
        await notifyIntervalResults();
        console.log("[CRON] Interval recap complete.");
      } catch (error: any) {
        console.error("[CRON] Error sending interval recap:", error.message);
      }
    },
    {
      timezone: "America/New_York",
    },
  );

  // Check for competitions ending tomorrow at 6 PM ET
  cron.schedule(
    "0 18 * * *",
    async () => {
      console.log("[CRON] Checking competitions ending soon...");
      try {
        await checkCompetitionsEndingSoon();
        console.log("[CRON] Ending soon check complete.");
      } catch (error: any) {
        console.error("[CRON] Error checking ending soon:", error.message);
      }
    },
    {
      timezone: "America/New_York",
    },
  );

  // Every hour at :00 — fire daily "mile still waiting" reminders to users whose
  // current local hour matches their configured reminder hour and who haven't
  // completed today's mile. Per-user TZ filtering is in the SQL.
  cron.schedule("0 * * * *", async () => {
    console.log("[CRON] Sending pending daily reminders...");
    try {
      await sendPendingDailyReminders();
      console.log("[CRON] Daily reminder send complete.");
    } catch (error: any) {
      console.error("[CRON] Error sending daily reminders:", error.message);
    }

    // Expire stale pending-friend-notification rows (ask-mode). Lazy expiry on
    // read already guarantees correctness; this is hygiene to keep the table tidy.
    try {
      await expireStalePendingNotifications();
    } catch (error: any) {
      console.error(
        "[CRON] Error expiring stale pending notifications:",
        error.message,
      );
    }
  });

  // Every hour at :35 — remind users about friend requests they've left
  // unanswered for >24h. Off unless FRIEND_REQUEST_REMINDERS=true (the service
  // returns immediately otherwise); see friendRequestFeatures.ts. Minute 35 is
  // clear of the other hourly jobs (:00 daily reminders, :10 streak features,
  // :20 h2h, :50 weekly recap). Per-user TZ + cooldown filtering is in the SQL.
  cron.schedule("35 * * * *", async () => {
    try {
      await sendPendingFriendRequestReminders();
    } catch (error: any) {
      console.error(
        "[CRON] Error sending friend request reminders:",
        error.message,
      );
    }
  });

  // Clean up old notification logs at 3 AM ET daily
  cron.schedule(
    "0 3 * * *",
    async () => {
      console.log("[CRON] Cleaning up old notification logs...");
      try {
        await cleanupNotificationLogs();
        console.log("[CRON] Notification log cleanup complete.");
      } catch (error: any) {
        console.error("[CRON] Error cleaning up logs:", error.message);
      }
    },
    {
      timezone: "America/New_York",
    },
  );

  // Reconcile stored current_streak values every 6 hours. refreshCurrentStreak
  // only runs on workout upload, so streaks of users who stopped running go
  // stale (a stuck "1" on the streak leaderboard / public-streak endpoint).
  // Running every 6h keeps the leaderboard fresh across timezones as each
  // user's local day rolls over. Bounded to users with current_streak > 0.
  cron.schedule("0 */6 * * *", async () => {
    console.log("[CRON] Reconciling stale streaks...");
    try {
      const { checked, changed } = await reconcileStaleStreaks();
      console.log(
        `[CRON] Streak reconcile complete: ${changed}/${checked} updated.`,
      );
    } catch (error: any) {
      console.error("[CRON] Error reconciling streaks:", error.message);
    }
  });

  console.log(
    "Notification cron jobs scheduled (hourly daily-reminder + streak reconcile every 6h + 3 AM, 9 AM, 6 PM ET).",
  );
}
