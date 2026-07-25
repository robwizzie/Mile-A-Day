import { Client } from "pg";
import {
  FEED_MIN_DISTANCE,
  FEED_MIN_DURATION,
  FEED_QUALIFYING_DISTANCE,
} from "../services/workoutService.js";

/**
 * One-time classification of the `workouts` back catalogue into `feed_role`,
 * plus the partial index the unified feed reads through.
 *
 * Why this isn't in migration 0029
 * --------------------------------
 * Migrations run at BOOT, in one transaction, over the shared pool — which pins
 * `statement_timeout` and node-postgres' client-side `query_timeout` to 30s
 * (DbService.ts). A whole-table UPDATE or CREATE INDEX that overran 30s would
 * abort the migration, leave it unrecorded, and re-attempt the same doomed work
 * on the next boot: a boot loop, on a deploy model with no shell access. So the
 * migration adds only the (instant, metadata-only) column, and the expensive
 * half happens here — after the server is already listening and serving.
 *
 * Safe to be mid-flight: an unclassified row reads 'extra', which is exactly the
 * pre-feature behaviour (one card per workout). Users see the old feed until
 * their rows are converted, never a broken one.
 *
 * Resumable and idempotent. Work is chunked one user at a time — hundreds of
 * rows each, milliseconds — so nothing holds a long lock or a long transaction,
 * and `feed_role IS DISTINCT FROM` makes a second pass write nothing.
 */

// Built last, so its existence is the "backfill finished" marker — no extra
// bookkeeping table needed. A crash mid-run just means it isn't there yet and
// the next boot redoes the (idempotent) work.
const INDEX_NAME = "idx_workouts_feed_candidates";

/**
 * Per-user classification across ALL that user's days at once.
 *
 * Same rule as feedRoleStatements (workoutService) — see its comment for why
 * junk counts toward the day total but can't anchor it, and why this ranks
 * rather than compares timestamps. The one deliberate difference: there's no
 * anchor stickiness here, because nothing has been classified yet, so there is
 * no previous anchor to preserve.
 */
const CLASSIFY_USER_SQL = `
WITH day AS (
	SELECT
		workout_id,
		local_date,
		(distance >= $2 AND total_duration >= $3) AS substantive,
		ROW_NUMBER() OVER (
			PARTITION BY local_date ORDER BY device_end_date, workout_id
		) AS rn,
		SUM(distance) OVER (
			PARTITION BY local_date ORDER BY device_end_date, workout_id
			ROWS UNBOUNDED PRECEDING
		) AS cumulative
	FROM workouts
	WHERE user_id = $1 AND deleted_at IS NULL AND exclusion_reason IS NULL
),
crossing AS (
	SELECT local_date, MIN(rn) AS rn
	FROM day WHERE cumulative + 1e-9 >= $4
	GROUP BY local_date
),
anchor AS (
	SELECT d.local_date, MAX(d.rn) AS rn
	FROM day d
	JOIN crossing c ON c.local_date = d.local_date
	WHERE d.substantive AND d.rn <= c.rn
	GROUP BY d.local_date
),
roles AS (
	SELECT d.workout_id, CASE
		WHEN a.rn IS NULL THEN 'hidden'
		WHEN NOT d.substantive THEN 'hidden'
		WHEN d.rn = a.rn THEN 'daily_mile'
		WHEN d.rn < a.rn THEN 'rolled_up'
		ELSE 'extra'
	END AS role
	FROM day d
	LEFT JOIN anchor a ON a.local_date = d.local_date
)
UPDATE workouts w SET feed_role = r.role
FROM roles r
WHERE w.workout_id = r.workout_id AND w.user_id = $1
	AND w.feed_role IS DISTINCT FROM r.role`;

const HIDE_INACTIVE_SQL = `
UPDATE workouts SET feed_role = 'hidden'
WHERE user_id = $1
	AND (deleted_at IS NOT NULL OR exclusion_reason IS NOT NULL)
	AND feed_role <> 'hidden'`;

/**
 * Is the marker index present AND usable?
 *
 * `indisvalid` is the important half: a CREATE INDEX CONCURRENTLY that fails
 * partway leaves the index behind in an INVALID state, which the planner
 * ignores. Checking mere existence would read that corpse as "backfill
 * finished" and skip the work forever, leaving an unusable index in place.
 */
async function validIndexExists(client: Client): Promise<boolean> {
  const { rows } = await client.query<{ exists: boolean }>(
    `SELECT EXISTS (
			SELECT 1 FROM pg_class c
			JOIN pg_index i ON i.indexrelid = c.oid
			WHERE c.relname = $1 AND i.indisvalid
		) AS exists`,
    [INDEX_NAME],
  );
  return rows[0]?.exists === true;
}

export async function backfillFeedRoles(): Promise<void> {
  // A dedicated connection, NOT one from the shared pool: the pool's 30s
  // statement/query timeouts are right for request handling and wrong for a
  // maintenance sweep. CREATE INDEX CONCURRENTLY additionally cannot run inside
  // a transaction, which rules out the pool's transaction helper.
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    statement_timeout: 0,
    query_timeout: 0,
  });

  try {
    await client.connect();

    if (await validIndexExists(client)) return;

    // Clear an invalid leftover from a previous interrupted run — IF NOT EXISTS
    // below would otherwise happily skip past it and leave it unusable.
    await client.query(`DROP INDEX IF EXISTS ${INDEX_NAME}`);

    console.log("[feed-roles] backfill starting");
    const started = Date.now();
    let processed = 0;
    let cursor = "";

    // Keyset over users (a small table) rather than over workouts, so each
    // statement's window functions partition a single user's rows.
    for (;;) {
      const { rows } = await client.query<{ user_id: string }>(
        `SELECT user_id FROM users WHERE user_id > $1 ORDER BY user_id LIMIT 200`,
        [cursor],
      );
      if (rows.length === 0) break;

      for (const { user_id } of rows) {
        await client.query(HIDE_INACTIVE_SQL, [user_id]);
        await client.query(CLASSIFY_USER_SQL, [
          user_id,
          FEED_MIN_DISTANCE,
          FEED_MIN_DURATION,
          FEED_QUALIFYING_DISTANCE,
        ]);
        processed++;
      }
      cursor = rows[rows.length - 1].user_id;
    }

    // Only now that every row holds its real role — building it first would
    // mean every backfill UPDATE also churned the index, roughly doubling the
    // write cost and the bloat. CONCURRENTLY so live traffic keeps writing.
    await client.query(
      `CREATE INDEX CONCURRENTLY IF NOT EXISTS ${INDEX_NAME}
			ON workouts (user_id, device_end_date DESC)
			WHERE deleted_at IS NULL AND exclusion_reason IS NULL
				AND feed_role IN ('daily_mile', 'extra')`,
    );

    console.log(
      `[feed-roles] backfill done — ${processed} user(s) in ${Math.round((Date.now() - started) / 1000)}s`,
    );
  } catch (err) {
    // Never take the server down for this. Un-backfilled rows read 'extra',
    // which is the pre-feature behaviour, and the next boot retries.
    console.error("[feed-roles] backfill failed (will retry next boot):", err);
  } finally {
    await client.end().catch(() => {});
  }
}
