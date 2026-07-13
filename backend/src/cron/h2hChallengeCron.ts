import cron from "node-cron";
import {
  resolveDueMatchups,
  notifyPendingWinners,
} from "../services/h2hMatchupService.js";

/**
 * Head-to-Head daily-challenge lifecycle:
 *  - resolveDueMatchups: scores each duel once BOTH users' local day is over
 *    (+ grace for late HealthKit syncs) and awards the winner's completion.
 *  - notifyPendingWinners: sends the "you won" push during the winner's local
 *    daytime instead of at the small-hours scoring moment.
 * Hourly so each timezone is picked up shortly after its own cutoffs pass;
 * both steps are idempotent per matchup, so re-runs are no-ops. :20 keeps it
 * clear of the :00 (daily reminders) and :50 (weekly recap) hourly jobs.
 */
export function startH2hChallengeCron(): void {
  cron.schedule("20 * * * *", async () => {
    try {
      await resolveDueMatchups();
    } catch (error: any) {
      console.error("[CRON] Error resolving H2H matchups:", error.message);
    }
    try {
      await notifyPendingWinners();
    } catch (error: any) {
      console.error("[CRON] Error notifying H2H winners:", error.message);
    }
  });

  console.log("H2H challenge cron scheduled (hourly resolve + winner notify).");
}
