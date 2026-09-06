import cron from "node-cron";
import { PostgresService } from "../services/DbService.js";
import { sendSilentPushToUser } from "../services/pushNotificationService.js";
import { runJob } from "./cronRunner.js";

const db = PostgresService.getInstance();

/**
 * Trigger the background-sync silent push for every user with a registered device token.
 * Exported so dev routes can invoke it on-demand.
 */
export async function runSilentSyncPushFanout(): Promise<{
  users: number;
  pushes: number;
}> {
  const rows = await db.query<{ user_id: string }>(
    `SELECT DISTINCT user_id FROM device_tokens`,
  );

  let pushes = 0;
  for (const { user_id } of rows) {
    try {
      pushes += await sendSilentPushToUser(user_id, "background_sync");
    } catch (err: any) {
      console.error(
        `[SilentSyncCron] Error pushing user ${user_id}:`,
        err.message,
      );
    }
  }

  return { users: rows.length, pushes };
}

async function fanout(label: string): Promise<void> {
  console.log(`[CRON] ${label} silent sync push fanout starting...`);
  const { users, pushes } = await runSilentSyncPushFanout();
  console.log(
    `[CRON] ${label} silent sync push fanout complete: ${users} users, ${pushes} pushes`,
  );
}

export function startSilentSyncCron(): void {
  // 8am, 12pm, 4pm, 8pm, and 11:45pm ET. The 11:45pm run flushes late-evening
  // workouts before midnight competition resolution / end-of-day tie checks.
  cron.schedule(
    "0 8,12,16,20 * * *",
    async () => {
      await runJob("sync.silent_fanout", () => fanout("Daytime"));
    },
    { timezone: "America/New_York" },
  );

  cron.schedule(
    "45 23 * * *",
    async () => {
      await runJob("sync.silent_fanout_premidnight", () =>
        fanout("Pre-midnight"),
      );
    },
    { timezone: "America/New_York" },
  );

  console.log(
    "Silent sync push cron scheduled (8am, 12pm, 4pm, 8pm, 11:45pm ET).",
  );
}
