import cron from "node-cron";
import { runJob } from "./cronRunner.js";
import { sweepAiCallLogs } from "../services/runPlans/coachSettings.js";
import { sendRunPlanProposalNotifications } from "../services/runPlans/notifications.js";
import { runNightlyPasses } from "../services/runPlans/triggers.js";

/**
 * Run Plans v2:
 *  - hourly at :40 — the nightly formula (and Anthropic) pass for plans whose
 *    owner's local clock is in the 3 AM hour;
 *  - every 15 min (:03/:18/:33/:48) — proposal pushes that are due (8 PM the
 *    evening before for early runners, else 9 AM);
 *  - daily 04:15 UTC — delete AI call logs older than 90 days.
 */
export function startRunPlansCron(): void {
  cron.schedule("40 * * * *", async () => {
    await runJob("run_plans.nightly", () => runNightlyPasses());
  });
  cron.schedule("3,18,33,48 * * * *", async () => {
    await runJob("run_plans.notify", () => sendRunPlanProposalNotifications());
  });
  cron.schedule("15 4 * * *", async () => {
    await runJob("run_plans.ai_log_sweep", () => sweepAiCallLogs());
  });
  console.log("Run Plans cron scheduled (nightly pass :40, notices every 15 min, AI log sweep 04:15 UTC).");
}
