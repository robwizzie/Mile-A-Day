import cron from "node-cron";
import { runStreakFeaturesSweep } from "../services/streakFeatureService.js";
import { streakFeaturesGloballyEnabled } from "../services/streakFeatureCore.js";

/**
 * Hourly streak-token sweep. Each run settles YESTERDAY for enrolled users
 * currently in their local morning (6–11): waits out an open Double Down
 * window, auto-consumes a held Streak Save, or stamps the break and offers
 * the rescue to assist-holding friends. Runs at :10 so it never lands on the
 * same tick as the :00 daily-reminder batch.
 *
 * Instant no-op while STREAK_FEATURES_ENABLED is unset — safe to deploy dark.
 */
export function startStreakFeaturesCron(): void {
  cron.schedule("10 * * * *", async () => {
    if (!streakFeaturesGloballyEnabled()) return;
    try {
      const { processed, saved, breaks } = await runStreakFeaturesSweep();
      if (processed > 0) {
        console.log(
          `[CRON] Streak-features sweep: ${processed} users, ${saved} saves, ${breaks} breaks.`,
        );
      }
    } catch (error: any) {
      console.error("[CRON] Streak-features sweep failed:", error.message);
    }
  });

  console.log("Streak-features cron scheduled (hourly sweep at :10).");
}
