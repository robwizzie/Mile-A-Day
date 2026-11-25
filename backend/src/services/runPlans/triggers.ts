import { PostgresService } from "../DbService.js";
import { userOffsetMinutesSql } from "../dailyResetTime.js";
import { maybeRunAnthropicInBackground } from "./anthropicCoach.js";
import { nightlyPass, onWorkoutsUploaded } from "./runPlanService.js";

/**
 * When the coach runs (spec §1, §5): after a workout uploads, on the first
 * app open of the day (POST /run-plans/open), and nightly. The formula pass
 * always runs server-side; the Anthropic pass only for ai_mode='anthropic'
 * (rate-limited). Apple-model passes happen on the phone.
 */

const db = PostgresService.getInstance();

/** Fire-and-forget from the workout upload. Never throws. */
export async function afterWorkoutUpload(userId: string, workoutIds: string[]): Promise<void> {
  try {
    await onWorkoutsUploaded(userId, workoutIds);
    const t = await db.query<{ today: string }>(
      `SELECT ((now() AT TIME ZONE 'UTC') + ${userOffsetMinutesSql("$1")} * INTERVAL '1 minute')::date::text AS today`,
      [userId],
    );
    void maybeRunAnthropicInBackground(userId, t[0].today, "after_run");
  } catch (e: any) {
    console.error("[runPlans] after-upload pass failed:", e?.code ?? e?.message ?? e);
  }
}

export const NIGHTLY_LOCAL_HOUR = 3;
/**
 * Hourly: every active plan whose owner's local clock is in the 3 AM hour
 * gets its nightly pass (claimed once per local day on last_nightly_date).
 */
export async function runNightlyPasses(now: Date = new Date()): Promise<{ due: number; ran: number }> {
  const rows = await db.query<{ user_id: string; local_today: string }>(
    `SELECT rp.user_id, (($1::timestamptz AT TIME ZONE 'UTC') + o.off * INTERVAL '1 minute')::date::text AS local_today
       FROM run_plans rp
       CROSS JOIN LATERAL (SELECT ${userOffsetMinutesSql("rp.user_id")} AS off) o
      WHERE rp.status = 'active'
        AND EXTRACT(HOUR FROM (($1::timestamptz AT TIME ZONE 'UTC') + o.off * INTERVAL '1 minute')) = $2
        AND (rp.last_nightly_date IS NULL OR rp.last_nightly_date < (($1::timestamptz AT TIME ZONE 'UTC') + o.off * INTERVAL '1 minute')::date)`,
    [now.toISOString(), NIGHTLY_LOCAL_HOUR],
  );
  let ran = 0;
  for (const r of rows) {
    try {
      if (await nightlyPass(r.user_id, r.local_today)) {
        ran++;
        await maybeRunAnthropicInBackground(r.user_id, r.local_today, "nightly");
      }
    } catch (e: any) {
      console.error("[runPlans] nightly pass failed for", r.user_id, e?.code ?? e?.message ?? e);
    }
  }
  return { due: rows.length, ran };
}
