import cron from "node-cron";
import { runJob } from "./cronRunner.js";
import { pruneOldDiagnostics } from "../services/diagnosticsService.js";

/** Daily at 4:20 AM ET: drop MetricKit rows past the retention window. */
export function startDiagnosticsCron(): void {
  cron.schedule(
    "20 4 * * *",
    async () => {
      await runJob("diagnostics.prune", async () => {
        await pruneOldDiagnostics();
      });
    },
    { timezone: "America/New_York" },
  );
  console.log("Diagnostics cron scheduled (4:20 AM ET retention prune).");
}
