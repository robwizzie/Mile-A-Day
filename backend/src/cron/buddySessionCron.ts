import cron from "node-cron";
import { buddySessionsEnabled } from "../services/buddyFeatures.js";
import { sweepAbandonedSessions } from "../services/buddySessionService.js";

/**
 * Buddy session backstop sweep.
 *
 * Deliberately narrow. Session finalization is LAZY — finalizeIfDue runs on
 * every state read and every progress report, which is what lets a race_time
 * session end punctually without a per-minute cron (the same "recompute on
 * read" shape competitions use for standings). Live "out of range" display is
 * likewise derived at read time from last_progress_at.
 *
 * So this job exists only for the case no read can cover: every participant's
 * app died, nobody is polling, and the session would otherwise sit 'active'
 * forever. It also cancels lobbies nobody ever started.
 *
 * :05 keeps it clear of the taken hourly slots (:00 daily reminders, :10 streak
 * features, :20 H2H, :35 friend-request reminders, :50 weekly recap).
 *
 * Registered unconditionally but no-ops while the feature flag is off, matching
 * how friendRequestReminderService's cron is wired.
 */
export function startBuddySessionCron(): void {
  cron.schedule("5 * * * *", async () => {
    if (!buddySessionsEnabled()) return;
    try {
      const swept = await sweepAbandonedSessions();
      if (swept > 0) {
        console.log(`[CRON] Swept ${swept} abandoned buddy session(s).`);
      }
    } catch (error: any) {
      console.error(
        "[CRON] Error sweeping abandoned buddy sessions:",
        error.message,
      );
    }
  });

  console.log("Buddy session cron scheduled (hourly abandoned-session sweep).");
}
