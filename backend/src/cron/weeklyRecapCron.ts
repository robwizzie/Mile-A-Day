import cron from "node-cron";
import { runJob } from "./cronRunner.js";
import { sendWeeklyRecaps } from "../services/weeklyRecapService.js";

/**
 * Hourly at :50 — the Weekly Recap push for users whose local clock just
 * turned 19:00 (20:00 when the daily reminder owns 19) on the week's last day,
 * Saturday. :50 keeps it clear of the :00 daily-reminder batch and the other
 * hourly jobs (:05 last call, :10 streak features, :20 h2h + weekly challenge,
 * :25, :35 friend-request reminders). Who is due, the per-device gate and the
 * once-per-week claim all live in weeklyRecapService; the kill switch is
 * WEEKLY_RECAP_DISABLED.
 */
export function startWeeklyRecapCron(): void {
  cron.schedule("50 * * * *", async () => {
    await runJob("weekly_recap.send", () => sendWeeklyRecaps());
  });

  console.log("Weekly recap cron scheduled (hourly at :50, local Sat 7 PM).");
}
