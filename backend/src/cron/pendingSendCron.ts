import cron from "node-cron";
import { drainDueScheduled } from "../services/pendingNotificationService.js";
import { runJob } from "./cronRunner.js";

/**
 * Delivers time-delayed friend notifications once their delay elapses — today
 * that's the deferred mile-completion push (run time + ~10 min) that merges a
 * post-run photo into a single notification. Runs about once a minute.
 */
export function startPendingSendCron(): void {
  // Off the :00 second/every-minute default a hair to avoid clustering with
  // other minute jobs.
  cron.schedule("* * * * *", async () => {
    await runJob("notifications.drain_scheduled", drainDueScheduled);
  });
  console.log(
    "[PendingSendCron] Scheduled scheduled-notification drain (every minute).",
  );
}
