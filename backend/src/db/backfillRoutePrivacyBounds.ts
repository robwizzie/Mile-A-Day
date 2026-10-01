import { Client } from "pg";

/**
 * One-time fill of `workout_routes.privacy_bounds` — the hide-start-&-end cut
 * for every offered setting — for routes stored before the column existed.
 *
 * Why this isn't in migration 0084/0085: same reasoning as backfillFeedRoles
 * — migrations run at BOOT over the shared pool with 30s timeouts, and a
 * sweep over every stored polyline could overrun and boot-loop the deploy.
 *
 * Safe to be mid-flight, which is the point of it being a CACHE: a NULL row
 * is trimmed at read by `mad_route_view_bounds` computing the cut on the
 * spot, so every route is already private the moment the deploy lands; this
 * only makes the read cheap. Resumable (keyset on workout_id, NULL rows only)
 * and idempotent; done-marker in maintenance_runs so later boots cost one
 * SELECT. Change the cut rule or the offered settings ⇒ bump the name (and
 * re-null the column in that change).
 */
export const ROUTE_PRIVACY_BOUNDS_BACKFILL = "route_privacy_bounds_v1";
const BATCH = 200;

export async function runRoutePrivacyBoundsBackfill(
  client: Client,
): Promise<{ skipped: boolean; routes: number }> {
  const done = await client.query(
    `SELECT 1 FROM maintenance_runs WHERE name = $1`,
    [ROUTE_PRIVACY_BOUNDS_BACKFILL],
  );
  if (done.rowCount) return { skipped: true, routes: 0 };

  let routes = 0;
  let cursor = "";
  for (;;) {
    const { rows } = await client.query<{ workout_id: string }>(
      `WITH batch AS (
				SELECT workout_id FROM workout_routes
				 WHERE workout_id > $1
				 ORDER BY workout_id
				 LIMIT ${BATCH}
			)
			UPDATE workout_routes wr
			   SET privacy_bounds = mad_route_privacy_bounds(wr.route, wr.workout_id)
			  FROM batch
			 WHERE wr.workout_id = batch.workout_id
			   AND wr.privacy_bounds IS NULL
			RETURNING wr.workout_id`,
      [cursor],
    );
    // The batch's LAST key moves the cursor even when every row in it was
    // already filled (the sync path writes it for new routes).
    const last = await client.query<{ workout_id: string }>(
      `SELECT workout_id FROM workout_routes
			  WHERE workout_id > $1 ORDER BY workout_id LIMIT 1 OFFSET ${BATCH - 1}`,
      [cursor],
    );
    routes += rows.length;
    if (!last.rows[0]) break;
    cursor = last.rows[0].workout_id;
  }

  await client.query(
    `INSERT INTO maintenance_runs (name, completed_at, detail)
		 VALUES ($1, NOW(), $2)
		 ON CONFLICT (name) DO UPDATE SET completed_at = EXCLUDED.completed_at, detail = EXCLUDED.detail`,
    [ROUTE_PRIVACY_BOUNDS_BACKFILL, JSON.stringify({ routes })],
  );
  return { skipped: false, routes };
}

export async function backfillRoutePrivacyBounds(): Promise<void> {
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    statement_timeout: 0,
    query_timeout: 0,
  });
  try {
    await client.connect();
    const started = Date.now();
    const result = await runRoutePrivacyBoundsBackfill(client);
    if (!result.skipped) {
      console.log(
        `[route-privacy] bounds backfill done: ${result.routes} routes in ${Date.now() - started}ms`,
      );
    }
  } catch (err: any) {
    // Never fatal: an unfilled row is computed at read, so the only cost of
    // a failed run is speed until the next boot retries it.
    console.error("[route-privacy] bounds backfill failed:", err?.message ?? err);
  } finally {
    await client.end().catch(() => {});
  }
}
