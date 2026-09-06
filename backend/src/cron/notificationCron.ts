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
import { runJob } from "./cronRunner.js";

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
  // unchanged and continue to send immediately. Each step is its own job so
  // one failing never costs the next its turn.
  cron.schedule(
    "0 9 * * *",
    async () => {
      console.log("[CRON] 9 AM overnight notification batch starting...");
      await runJob("notifications.flush_batched", flushBatchedNotifications);
      await runJob("notifications.clash_ties", checkClashTies);
      await runJob("notifications.streaks_broken", checkStreaksBroken);
      await runJob("notifications.streak_life_loss", checkStreakLifeLoss);
      await runJob("notifications.target_missed", checkTargetMissed);
      await runJob("notifications.interval_results", notifyIntervalResults);
      console.log("[CRON] 9 AM overnight notification batch complete.");
    },
    {
      timezone: "America/New_York",
    },
  );

  // Check for competitions ending tomorrow at 6 PM ET
  cron.schedule(
    "0 18 * * *",
    async () => {
      await runJob("notifications.ending_soon", checkCompetitionsEndingSoon);
    },
    {
      timezone: "America/New_York",
    },
  );

  // Every hour at :00 — fire daily "mile still waiting" reminders to users whose
  // current local hour matches their configured reminder hour and who haven't
  // completed today's mile. Per-user TZ filtering is in the SQL.
  cron.schedule("0 * * * *", async () => {
    await runJob("notifications.daily_reminders", sendPendingDailyReminders);
    // Expire stale pending-friend-notification rows (ask-mode). Lazy expiry on
    // read already guarantees correctness; this is hygiene to keep the table tidy.
    await runJob(
      "notifications.expire_pending",
      expireStalePendingNotifications,
    );
  });

  // Every hour at :35 — remind users about friend requests they've left
  // unanswered for >24h. Reaches only devices declaring `friend_request_v2`,
  // and stops entirely on FRIEND_REQUEST_REMINDERS_DISABLED=true; see
  // friendRequestFeatures.ts and clientFeatures.ts. Minute 35 is
  // clear of the other hourly jobs (:00 daily reminders, :10 streak features,
  // :20 h2h, :50 weekly recap). Per-user TZ + cooldown filtering is in the SQL.
  cron.schedule("35 * * * *", async () => {
    await runJob(
      "notifications.friend_request_reminders",
      sendPendingFriendRequestReminders,
    );
  });

  // Clean up old notification logs at 3 AM ET daily
  cron.schedule(
    "0 3 * * *",
    async () => {
      await runJob("notifications.cleanup_logs", cleanupNotificationLogs);
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
    await runJob("streaks.reconcile_stale", async () => {
      const { checked, changed } = await reconcileStaleStreaks();
      console.log(
        `[CRON] Streak reconcile complete: ${changed}/${checked} updated.`,
      );
    });
  });

  console.log(
    "Notification cron jobs scheduled (hourly daily-reminder + streak reconcile every 6h + 3 AM, 9 AM, 6 PM ET).",
  );
}
