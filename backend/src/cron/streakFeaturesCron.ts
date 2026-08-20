import cron from "node-cron";
import { runStreakFeaturesSweep } from "../services/streakFeatureService.js";
import { streakFeaturesGloballyEnabled } from "../services/streakFeatureCore.js";
import { expirePausesPastCap } from "../services/injuryPauseService.js";

/**
 * Hourly streak-token sweep. Each run settles YESTERDAY for enrolled users
 * currently in their local morning (6–11): waits out an open Double Down
 * window, auto-consumes a held Streak Save, or stamps the break and offers
 * the rescue to assist-holding friends. Runs at :10 so it never lands on the
 * same tick as the :00 daily-reminder batch.
 *
 * Only enrolled users are processed (none exist until a token-UI build runs),
 * and STREAK_FEATURES_DISABLED=true freezes the sweep entirely.
 */
export function startStreakFeaturesCron(): void {
  cron.schedule("10 * * * *", async () => {
    if (!streakFeaturesGloballyEnabled()) return;

    // Retire injury pauses past the 180-day cap first, so the sweep below
    // settles those users as unpaused. Isolated: a failure here must not cost
    // everyone else their sweep.
    try {
      const expired = await expirePausesPastCap();
      if (expired > 0) {
        console.log(`[CRON] Injury pauses past cap expired: ${expired}.`);
      }
    } catch (error: any) {
      console.error("[CRON] Injury-pause cap sweep failed:", error.message);
    }

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
