import { Client } from "pg";
import { streakFeaturesGloballyEnabled } from "../services/streakFeatureCore.js";

/**
 * One-time fill of `users.longest_streak` from each user's full workout
 * history, plus the index the streak-record surfaces can read through.
 *
 * Why this isn't in migration 0034
 * --------------------------------
 * Same reasoning as backfillFeedRoles (see its header): migrations run at
 * BOOT over the shared pool with 30s timeouts, one transaction each — a
 * history sweep or CREATE INDEX that overran would boot-loop the deploy. The
 * migration adds only the instant, constant-default column; the history scan
 * happens here, after the server is listening.
 *
 * Safe to be mid-flight: an unfilled row reads 0, and every API surface
 * degrades that to max(0, current streak) — i.e. exactly the information the
 * app had before this feature. The ratcheting writers (refreshCurrentStreak,
 * ratchetLongestStreak) keep values correct from "now" onward regardless.
 *
 * Resumable and idempotent: one GREATEST() UPDATE per user, milliseconds
 * each, no long locks; a second pass can only re-write equal values.
 */

// Built last, so its (valid) existence is the "backfill finished" marker —
// same bookkeeping-free pattern as backfillFeedRoles.
const INDEX_NAME = "idx_users_longest_streak_desc";

/**
 * Longest consecutive run over the user's qualified-or-covered days, folded
 * into users.longest_streak with GREATEST (concurrent refreshCurrentStreak
 * writes can never be regressed by this).
 *
 * The gaps-and-islands grouping mirrors streakEndingAt (streakFeatureCore),
 * and the qualifying-day rule is the walks' own: SUM(distance) >= 0.95 over
 * non-deleted, non-excluded workouts. Coverage days are UNIONed in only for
 * enrolled users while the feature is globally on — the same gate
 * coverageActiveFor applies to the live walks, so token-covered days count
 * for exactly the users whose streaks count them.
 */
function longestRunUpdateSql(includeCoverage: boolean): string {
  return `
WITH days AS (
	SELECT local_date FROM workouts
	WHERE user_id = $1 AND deleted_at IS NULL AND exclusion_reason IS NULL
	GROUP BY local_date HAVING SUM(distance) >= 0.95
	${includeCoverage ? "UNION\n\tSELECT local_date FROM streak_coverage WHERE user_id = $1" : ""}
),
numbered AS (
	SELECT local_date,
	       local_date - (ROW_NUMBER() OVER (ORDER BY local_date))::int AS grp
	FROM days
),
runs AS (
	SELECT COUNT(*)::int AS len FROM numbered GROUP BY grp
)
UPDATE users
SET longest_streak = GREATEST(longest_streak, (SELECT COALESCE(MAX(len), 0) FROM runs))
WHERE user_id = $1`;
}

/**
 * Is the marker index present AND usable? `indisvalid` matters: an
 * interrupted CREATE INDEX CONCURRENTLY leaves an INVALID corpse the planner
 * ignores — mere existence would read that as "finished" forever.
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

export async function backfillLongestStreaks(): Promise<void> {
  // Dedicated connection, NOT the shared pool: the pool's 30s timeouts are
  // wrong for a maintenance sweep, and CREATE INDEX CONCURRENTLY cannot run
  // inside a transaction.
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    statement_timeout: 0,
    query_timeout: 0,
  });

  try {
    await client.connect();

    if (await validIndexExists(client)) return;

    // Clear an invalid leftover from a previous interrupted run.
    await client.query(`DROP INDEX IF EXISTS ${INDEX_NAME}`);

    console.log("[longest-streaks] backfill starting");
    const started = Date.now();
    const globallyEnabled = streakFeaturesGloballyEnabled();
    let processed = 0;
    let cursor = "";

    for (;;) {
      const { rows } = await client.query<{
        user_id: string;
        enrolled: boolean;
      }>(
        `SELECT user_id, (streak_features_at IS NOT NULL) AS enrolled
				 FROM users WHERE user_id > $1 ORDER BY user_id LIMIT 200`,
        [cursor],
      );
      if (rows.length === 0) break;

      for (const { user_id, enrolled } of rows) {
        await client.query(longestRunUpdateSql(enrolled && globallyEnabled), [
          user_id,
        ]);
        processed++;
      }
      cursor = rows[rows.length - 1].user_id;
    }

    // Built after the fill so the backfill UPDATEs don't churn it;
    // CONCURRENTLY so live traffic keeps writing.
    await client.query(
      `CREATE INDEX CONCURRENTLY IF NOT EXISTS ${INDEX_NAME}
			ON users (longest_streak DESC)`,
    );

    console.log(
      `[longest-streaks] backfill done — ${processed} user(s) in ${Math.round((Date.now() - started) / 1000)}s`,
    );
  } catch (err) {
    // Never take the server down for this. Unfilled rows read 0 → API
    // degrades to the current streak, and the next boot retries.
    console.error(
      "[longest-streaks] backfill failed (will retry next boot):",
      err,
    );
  } finally {
    await client.end().catch(() => {});
  }
}
