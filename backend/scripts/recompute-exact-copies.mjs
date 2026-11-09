/**
 * One-off: re-run duplicate detection on every (user, day) that holds an
 * exact same-app copy, so history picks up the rule added for apps that write
 * one activity to HealthKit more than once (Strava, Garmin Connect, Fitbit,
 * Oura). New syncs get it on their own; this catches days nobody re-syncs.
 *
 * Read-only unless --apply. Excluding never deletes: rows get
 * exclusion_reason = 'duplicate_source', which WORKOUT_DEDUPE=false or a
 * user's "count it" answer reverses.
 *
 * Usage (from backend/, after `npm run build`):
 *   DATABASE_URL=... node scripts/recompute-exact-copies.mjs          # report
 *   DATABASE_URL=... node scripts/recompute-exact-copies.mjs --apply  # write
 */
import { PostgresService } from "../dist/services/DbService.js";
import { recomputeDuplicatesForDay } from "../dist/services/workoutService.js";

const apply = process.argv.includes("--apply");
const db = PostgresService.getInstance();

// Same tolerances as exactCopySql() in workoutService.ts.
const days = await db.query(
  `SELECT DISTINCT a.user_id, to_char(a.local_date, 'YYYY-MM-DD') AS local_date
     FROM workouts a
     JOIN workouts b
       ON b.user_id = a.user_id AND b.local_date = a.local_date
      AND b.workout_id < a.workout_id
      AND b.source_bundle_id = a.source_bundle_id
      AND abs(EXTRACT(EPOCH FROM (a.device_end_date - b.device_end_date))) <= 1
      AND abs(a.total_duration - b.total_duration) <= 1
      AND abs(a.distance - b.distance) <= 0.005
    WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL
      AND a.source_bundle_id IS NOT NULL AND a.total_duration > 0
    ORDER BY 1, 2`,
);

const counting = async () =>
  (await db.query(
    `SELECT count(*)::int AS n, coalesce(round(sum(distance)::numeric, 1), 0)::float AS mi
       FROM workouts w
      WHERE deleted_at IS NULL AND exclusion_reason IS NULL
        AND (user_id, local_date) IN (SELECT * FROM unnest($1::text[], $2::date[]))`,
    [days.map((d) => d.user_id), days.map((d) => d.local_date)],
  ))[0];

const users = new Set(days.map((d) => d.user_id)).size;
const before = await counting();
console.log(`${days.length} days across ${users} users hold exact copies.`);
console.log(`Counting on those days now: ${before.n} workouts, ${before.mi} mi.`);

if (!apply) {
  console.log("Dry run. Re-run with --apply to recompute them.");
  process.exit(0);
}

let done = 0;
for (const d of days) {
  await recomputeDuplicatesForDay(d.user_id, d.local_date);
  if (++done % 50 === 0) console.log(`  ${done}/${days.length}`);
}
const after = await counting();
console.log(`Done. Counting on those days now: ${after.n} workouts, ${after.mi} mi`
  + ` (${before.n - after.n} copies, ${Math.round((before.mi - after.mi) * 10) / 10} mi excluded).`);
process.exit(0);
