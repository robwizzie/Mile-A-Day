import cron from "node-cron";
import { runJob } from "./cronRunner.js";
import { sweepAppleRevocations } from "../services/appleSignInTokenService.js";

/** Hourly: retry Apple token revocations that failed at account deletion. */
export function startAppleRevocationCron(): void {
  cron.schedule("35 * * * *", async () => {
    await runJob("apple.revocations", sweepAppleRevocations);
  });
  console.log("Apple token revocation cron scheduled (hourly at :35).");
}
