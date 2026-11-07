import cron from "node-cron";
import { PostgresService } from "../services/DbService.js";
import { runJob } from "./cronRunner.js";
import { sendPush } from "../services/pushNotificationService.js";
import { CLIENT_FEATURES, userSupports } from "../services/clientFeatures.js";
import { settleReferrals } from "../services/referralService.js";

const db = PostgresService.getInstance();

export async function runReferralSettlement(): Promise<void> {
  for (const { referrer_id, referee_id, count, notify } of await settleReferrals()) {
    try {
      if (!notify) continue;
      if (!(await userSupports(referrer_id, CLIENT_FEATURES.referralsV1))) continue;
      const [friend] = await db.query<{ first_name: string | null; username: string | null }>(
        `SELECT first_name, username FROM users WHERE user_id = $1`,
        [referee_id],
      );
      const name = friend?.first_name || friend?.username || "Your friend";
      await sendPush(referrer_id, {
        title: "A referral just counted",
        body: `${name} has walked 7 days. That's ${count} ${count === 1 ? "referral" : "referrals"}.`,
        type: "referral_qualified",
        data: { type: "referral_qualified", count: String(count) },
      });
    } catch (error: any) {
      console.error(`[referrals] Push failed for ${referrer_id}:`, error?.message ?? error);
    }
  }
}

export function startReferralCron(): void {
  cron.schedule("20 * * * *", () => {
    void runJob("referral-settlement", runReferralSettlement);
  });
}
