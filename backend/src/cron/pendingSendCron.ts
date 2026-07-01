import cron from "node-cron";
import { drainDueScheduled } from "../services/pendingNotificationService.js";

/**
 * Delivers time-delayed friend notifications once their delay elapses — today
 * that's the deferred mile-completion push (run time + ~10 min) that merges a
 * post-run photo into a single notification. Runs about once a minute.
 */
export function startPendingSendCron(): void {
  // Off the :00 second/every-minute default a hair to avoid clustering with
  // other minute jobs.
  cron.schedule("* * * * *", async () => {
    try {
      await drainDueScheduled();
    } catch (err: any) {
      console.error("[PendingSendCron] drain failed:", err?.message ?? err);
    }
  });
  console.log(
    "[PendingSendCron] Scheduled scheduled-notification drain (every minute).",
  );
}
