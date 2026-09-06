import cron from "node-cron";
import { resolveExpiredCompetitions } from "../services/competitionService.js";
import { runJob } from "./cronRunner.js";

export function startCompetitionCron(): void {
  // Competition resolution itself runs at midnight ET so finished comps
  // transition state on the correct calendar day. The user-visible
  // "competition_finished" pushes that fall out of this are already routed
  // through sendOrQueueCompetitionNotification, which queues them during
  // quiet hours and they get flushed by the 9 AM notification cron.
  // Clash tie detection moved to the 9 AM notification cron alongside the
  // other overnight-result notifications.
  cron.schedule(
    "0 0 * * *",
    async () => {
      console.log("[CRON] Running competition resolution...");
      await runJob("competitions.resolve_expired", resolveExpiredCompetitions);
    },
    {
      timezone: "America/New_York",
    },
  );

  console.log("Competition cron job scheduled (midnight ET).");
}
