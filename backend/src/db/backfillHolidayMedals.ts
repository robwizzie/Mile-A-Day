import { Client } from "pg";
import {
  holidayDayQualifiesSql,
  holidayProbeDates,
  seedExtraBadges,
} from "../services/badgeService.js";
import { countedWorkoutSql } from "../services/mileTime.js";
import { HOLIDAYS, HOLIDAY_BADGE_PREFIX } from "../services/holidays.js";

/**
 * One-time retroactive award of the `holiday_<key>` medals to everyone whose
 * history already holds a goal day on a holiday (the sync path only judges
 * the days an upload touches, so without this nobody who walked last
 * Halloween would ever get the Spooky Mile).
 *
 * Same contract as backfillFeedRoles / backfillLongestStreaks: post-listen,
 * not awaited, on a dedicated no-timeout client (migrations run at boot under
 * a 30s statement timeout, and a history sweep there would boot-loop the
 * deploy). Batched by user id, one INSERT … SELECT per batch, ON CONFLICT DO
 * NOTHING — so it is idempotent and resumable: an interrupted run just runs
 * again next boot and re-inserts nothing it already did.
 *
 * SILENT on purpose: rows go straight into user_badges, no push, no inbox row.
 * A retroactive medal is a discovery in the Medals screen (`is_new` stays at
 * its default TRUE, which is the in-app "new" dot), not news — a boot-time
 * burst of "Medal Unlocked" for last Christmas across the whole user base is
 * exactly the notification spam the push rules exist to prevent.
 *
 * Done-marker: a `maintenance_runs` row written only after the LAST batch, so
 * every later boot costs one SELECT. Grow the holiday catalog → bump the name.
 */
export const HOLIDAY_MEDALS_BACKFILL = "holiday_medals_v1";
const BATCH = 200;

/** Exported for scripts/flamey-check.mjs; the server calls the wrapper. */
export async function runHolidayMedalBackfill(
  client: Client,
  { force = false }: { force?: boolean } = {},
): Promise<{ skipped: boolean; users: number; awarded: number }> {
  if (!force) {
    const done = await client.query(
      `SELECT 1 FROM maintenance_runs WHERE name = $1`,
      [HOLIDAY_MEDALS_BACKFILL],
    );
    if (done.rowCount) return { skipped: true, users: 0, awarded: 0 };
  }

  // The FK on user_badges.badge_id needs the catalog rows; the boot seed is
  // fire-and-forget, so make sure rather than race it. Idempotent.
  await seedExtraBadges();
  // seedExtraBadges logs and swallows its own failure. Writing the done-marker
  // over a missing catalog would award nothing and never try again.
  const catalog = await client.query(
    `SELECT COUNT(*)::int AS n FROM badges WHERE badge_id LIKE '${HOLIDAY_BADGE_PREFIX}%'`,
  );
  if ((catalog.rows[0]?.n ?? 0) < HOLIDAYS.length) {
    throw new Error("holiday badges missing from the catalog");
  }

  const probe = holidayProbeDates();
  const dates = probe.map((p) => p.date);
  const keys = probe.map((p) => p.key);

  let users = 0;
  let awarded = 0;
  let cursor = "";
  for (;;) {
    const { rows } = await client.query<{ user_id: string }>(
      `SELECT user_id FROM users WHERE user_id > $1 ORDER BY user_id LIMIT ${BATCH}`,
      [cursor],
    );
    if (rows.length === 0) break;
    const ids = rows.map((r) => r.user_id);

    // Earliest qualifying day per (user, holiday) is the medal's trigger —
    // one row per medal, DISTINCT ON keeps it deterministic.
    const res = await client.query(
      `WITH hol AS (
				SELECT * FROM unnest($2::date[], $3::text[]) AS h(d, key)
			),
			days AS (
				SELECT w.user_id, w.local_date,
				       (ARRAY_AGG(w.workout_id ORDER BY w.device_end_date DESC))[1] AS workout_id
				FROM workouts w
				JOIN users u ON u.user_id = w.user_id
				WHERE w.user_id = ANY($1::text[])
				  AND w.local_date = ANY($2::date[])
				  AND ${countedWorkoutSql("w")}
				GROUP BY w.user_id, w.local_date, u.goal_miles
				HAVING ${holidayDayQualifiesSql("u", "w")}
			)
			INSERT INTO user_badges (user_id, badge_id, triggering_workout_id, progress_snapshot)
			SELECT DISTINCT ON (d.user_id, h.key)
			       d.user_id, '${HOLIDAY_BADGE_PREFIX}' || h.key, d.workout_id,
			       jsonb_build_object('holiday_date', to_char(d.local_date, 'YYYY-MM-DD'), 'backfilled', true)
			FROM days d
			JOIN hol h ON h.d = d.local_date
			JOIN badges b ON b.badge_id = '${HOLIDAY_BADGE_PREFIX}' || h.key
			ORDER BY d.user_id, h.key, d.local_date
			ON CONFLICT (user_id, badge_id) DO NOTHING`,
      [ids, dates, keys],
    );
    awarded += res.rowCount ?? 0;
    users += ids.length;
    cursor = ids[ids.length - 1];
  }

  await client.query(
    `INSERT INTO maintenance_runs (name, completed_at, detail)
		 VALUES ($1, NOW(), $2)
		 ON CONFLICT (name) DO UPDATE SET completed_at = EXCLUDED.completed_at, detail = EXCLUDED.detail`,
    [HOLIDAY_MEDALS_BACKFILL, JSON.stringify({ users, awarded })],
  );
  return { skipped: false, users, awarded };
}

export async function backfillHolidayMedals(): Promise<void> {
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    statement_timeout: 0,
    query_timeout: 0,
  });
  try {
    await client.connect();
    const started = Date.now();
    const r = await runHolidayMedalBackfill(client);
    if (!r.skipped) {
      console.log(
        `[holiday-medals] backfill done — ${r.awarded} medal(s) over ${r.users} user(s) in ${Math.round((Date.now() - started) / 1000)}s`,
      );
    }
  } catch (err) {
    // Never take the server down for this; the next boot retries.
    console.error("[holiday-medals] backfill failed (will retry next boot):", err);
  } finally {
    await client.end().catch(() => {});
  }
}
