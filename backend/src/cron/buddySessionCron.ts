import cron from "node-cron";
import { buddySessionsEnabled } from "../services/buddyFeatures.js";
import {
  promoteDueScheduledSessions,
  sweepAbandonedSessions,
} from "../services/buddySessionService.js";
import { spawnDueRecurringWalks } from "../services/buddyRecurringService.js";
import { sweepCrewPhotoNudges } from "../services/postService.js";

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
 * It ALSO promotes scheduled walks, which is why the cadence is every 5
 * minutes rather than hourly: "start at 6:00" cannot be honoured by a job that
 * runs on the hour. The sweep is a single indexed query that returns nothing
 * almost always, so 12x the frequency costs essentially nothing. Promotion is
 * additionally lazy on every state read, so a session whose lobby someone is
 * watching starts the instant it is due rather than at the next tick.
 *
 * Registered unconditionally but no-ops while the feature flag is off, matching
 * how friendRequestReminderService's cron is wired.
 */
export function startBuddySessionCron(): void {
  cron.schedule("*/5 * * * *", async () => {
    if (!buddySessionsEnabled()) return;
    try {
      // Routines BEFORE promotion: a routine spawns a session with a
      // scheduled start, and doing it in this order means one that's already
      // due gets promoted on the same tick instead of waiting five minutes.
      const spawned = await spawnDueRecurringWalks();
      if (spawned > 0) {
        console.log(`[CRON] Spawned ${spawned} recurring buddy walk(s).`);
      }
    } catch (error: any) {
      console.error(
        "[CRON] Error spawning recurring buddy walks:",
        error.message,
      );
    }
    try {
      // Scheduled walks first: starting one late is worse than reaping an
      // abandoned one late.
      await promoteDueScheduledSessions();
    } catch (error: any) {
      console.error(
        "[CRON] Error promoting scheduled buddy sessions:",
        error.message,
      );
    }
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
    try {
      // "3 of you were out, 1 photo so far" — an hour after the walk, for
      // participants who haven't put their own picture on its post yet. The
      // 5-minute cadence is why the window can be a tight one-to-six hours:
      // nothing waits long for its tick.
      const nudged = await sweepCrewPhotoNudges();
      if (nudged > 0) {
        console.log(`[CRON] Sent ${nudged} crew-photo nudge(s).`);
      }
    } catch (error: any) {
      console.error("[CRON] Error sending crew-photo nudges:", error.message);
    }
  });

  console.log(
    "Buddy session cron scheduled (5-min routine spawn + scheduled-start promotion + sweep).",
  );
}
