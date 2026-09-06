import cron from "node-cron";
import { sendPendingLastCalls } from "../services/lastCallService.js";

/**
 * Hourly at :05 — the streak last call for users whose local clock just
 * turned 22:00 with a live streak and no mile (lastCallService). :05 keeps
 * it clear of the :00 daily-reminder batch and the other hourly jobs
 * (:10 streak features, :20 h2h, :35 friend-request reminders, :50 recap).
 * The per-user timezone + "already ran today" arithmetic is in the SQL.
 */
export function startLastCallCron(): void {
  cron.schedule("5 * * * *", async () => {
    try {
      await sendPendingLastCalls();
    } catch (error: any) {
      console.error("[CRON] Error sending streak last calls:", error.message);
    }
  });

  console.log("Streak last-call cron scheduled (hourly at :05, local 10 PM).");
}
