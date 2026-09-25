import { Client } from "pg";
import { HOLIDAY_BADGE_PREFIX } from "../services/holidays.js";

/**
 * One-time repair of holiday medals dated to the deploy that backfilled them.
 *
 * The first holiday backfill (`holiday_medals_v1`), the retro sweep
 * (`badge_retro_v1`) and Recalibrate all inserted `user_badges` rows with
 * `earned_at` left at its DEFAULT now(). So a medal for walking last
 * Halloween read "earned today" on the Medals screen, and the app — which
 * celebrates every newly-arrived medal dated today — popped one unlock per
 * holiday on the first open after the deploy. The writers now stamp the
 * qualifying walk's time; this puts the rows already written back on the day
 * they were actually earned.
 *
 * What it writes, and only there:
 *   - holiday medals only (`holiday_%`) — the one family whose earned day is
 *     a fact on the row (its triggering workout, else the backfill's recorded
 *     `holiday_date`);
 *   - only where the stored date is MORE THAN TWO DAYS after that day, i.e.
 *     a medal the walk didn't earn when it synced. A live award (the walk
 *     synced within the day) is never touched.
 * The date it replaces is kept on the row (`progress_snapshot.stamped_at`),
 * so the change is reversible from the table alone.
 *
 * Same contract as the other post-listen tasks: not awaited, dedicated
 * no-timeout client, never takes the server down, done-marker in
 * `maintenance_runs` written after the update (every later boot is one
 * SELECT). Idempotent even without the marker — a repaired row no longer
 * matches. `HOLIDAY_MEDAL_DATE_REPAIR_DISABLED=1` turns it off.
 */
export const HOLIDAY_MEDAL_DATE_REPAIR = "holiday_medal_dates_v1";

/** Exported for scripts/flamey-check.mjs; the server calls the wrapper. */
export async function runHolidayMedalDateRepair(
  client: Client,
  { force = false }: { force?: boolean } = {},
): Promise<{ skipped: boolean; repaired: number }> {
  if (!force) {
    const done = await client.query(
      `SELECT 1 FROM maintenance_runs WHERE name = $1`,
      [HOLIDAY_MEDAL_DATE_REPAIR],
    );
    if (done.rowCount) return { skipped: true, repaired: 0 };
  }

  // The earned instant: the triggering workout's end (what every writer now
  // stamps), else noon UTC on the holiday the backfill recorded (its workout
  // may since have been deleted — the medal then survives on another year's
  // walk, but the day the row names is still the honest answer).
  const res = await client.query(
    `UPDATE user_badges ub
		 SET earned_at = src.earned_at,
		     progress_snapshot = COALESCE(ub.progress_snapshot, '{}'::jsonb)
		       || jsonb_build_object(
		            'stamped_at',
		            to_char(ub.earned_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
		          )
		 FROM (
		   SELECT b.id,
		          COALESCE(
		            w.device_end_date,
		            CASE WHEN b.progress_snapshot->>'holiday_date' ~ '^\\d{4}-\\d{2}-\\d{2}$'
		                 THEN ((b.progress_snapshot->>'holiday_date')::date + time '12:00') AT TIME ZONE 'UTC'
		            END
		          ) AS earned_at
		   FROM user_badges b
		   LEFT JOIN workouts w
		     ON w.workout_id = b.triggering_workout_id AND w.user_id = b.user_id
		   WHERE b.badge_id LIKE '${HOLIDAY_BADGE_PREFIX}%'
		 ) src
		 WHERE ub.id = src.id
		   AND src.earned_at IS NOT NULL
		   AND ub.earned_at > src.earned_at + interval '2 days'`,
  );
  const repaired = res.rowCount ?? 0;

  await client.query(
    `INSERT INTO maintenance_runs (name, completed_at, detail)
		 VALUES ($1, NOW(), $2)
		 ON CONFLICT (name) DO UPDATE SET completed_at = EXCLUDED.completed_at, detail = EXCLUDED.detail`,
    [HOLIDAY_MEDAL_DATE_REPAIR, JSON.stringify({ repaired })],
  );
  return { skipped: false, repaired };
}

export async function repairHolidayMedalDates(): Promise<void> {
  if (process.env.HOLIDAY_MEDAL_DATE_REPAIR_DISABLED === "1") return;
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    statement_timeout: 0,
    query_timeout: 0,
  });
  try {
    await client.connect();
    const r = await runHolidayMedalDateRepair(client);
    if (!r.skipped) {
      console.log(
        `[holiday-medals] re-dated ${r.repaired} medal(s) to the day they were earned`,
      );
    }
  } catch (err) {
    // Never take the server down for this; the next boot retries.
    console.error(
      "[holiday-medals] date repair failed (will retry next boot):",
      err,
    );
  } finally {
    await client.end().catch(() => {});
  }
}
