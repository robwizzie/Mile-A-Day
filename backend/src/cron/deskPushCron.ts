import cron from "node-cron";
import { runJob } from "./cronRunner.js";
import { runDeskPushChecks } from "../services/deskPushEvents.js";

/** Desk remote push notifications (new users, reviews, record days, the
 *  Versus lead, a desk going offline). A no-op without VAPID keys or with
 *  nobody subscribed. */
export function startDeskPushCron(): void {
  cron.schedule("* * * * *", async () => {
    await runJob("desk.push", runDeskPushChecks);
  });
  console.log("Desk push cron scheduled (every minute).");
}
