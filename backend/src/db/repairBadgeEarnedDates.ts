import { Client } from "pg";
import { redateBadges } from "../services/badgeEarnedDates.js";

/**
 * One-time repair: put every medal already on a shelf back on the day it was
 * EARNED.
 *
 * Until the evaluator learned to date its awards (services/badgeEarnedDates),
 * every `user_badges` insert left `earned_at` at its default now(). The one-time
 * sweeps that shipped with the all-history medal rules — `holiday_medals_v1`
 * and `badge_retro_v1` — therefore dated a whole history's worth of streak,
 * mileage, pace, daily-distance and holiday medals to the deploy instant, and
 * so did every Recalibrate and first-run import before them. The Medals
 * screen said "earned today" for a 500-day streak medal reached last spring,
 * and the app celebrated each one as today's news.
 *
 * Each user is re-dated by `redateBadges` — the same function every new award
 * now goes through — which only moves a date EARLIER, only past a 2-day slack
 * (a live award is never touched), leaves families with no dated history
 * (hypes, nudges, stories, competitions) alone, and keeps the replaced value
 * in `progress_snapshot.stamped_at` so the change is reversible from the
 * table. Idempotent: a re-dated row no longer qualifies.
 *
 * Same contract as backfillRetroBadges: post-listen, not awaited, never takes
 * the server down; the dedicated client only pages user ids and writes the
 * marker, and each user runs through the pool's ordinary per-user queries,
 * strictly one at a time with a pause between batches so live traffic gets
 * the pool first. The done-marker (`badge_earned_dates_v1`) is written only
 * when every user succeeded — a failure retries next boot, which is cheap
 * since already-repaired rows no longer match. `BADGE_DATE_REPAIR_DISABLED=1`
 * turns it off.
 */
export const BADGE_DATE_REPAIR = "badge_earned_dates_v1";
const BATCH = 100;
const PAUSE_MS = 250;

/** Exported for the check scripts; the server calls the wrapper. */
export async function runBadgeDateRepair(
  client: Client,
  {
    force = false,
    onlyUserIds,
  }: { force?: boolean; onlyUserIds?: string[] } = {},
): Promise<{
  skipped: boolean;
  users: number;
  repaired: number;
  failed: number;
}> {
  if (!force) {
    const done = await client.query(
      `SELECT 1 FROM maintenance_runs WHERE name = $1`,
      [BADGE_DATE_REPAIR],
    );
    if (done.rowCount)
      return { skipped: true, users: 0, repaired: 0, failed: 0 };
  }

  let users = 0;
  let repaired = 0;
  let failed = 0;
  let cursor = "";
  for (;;) {
    const { rows } = onlyUserIds
      ? await client.query<{ user_id: string }>(
          `SELECT DISTINCT user_id FROM user_badges
            WHERE user_id > $1 AND user_id = ANY($2::text[])
            ORDER BY user_id LIMIT ${BATCH}`,
          [cursor, onlyUserIds],
        )
      : await client.query<{ user_id: string }>(
          `SELECT DISTINCT user_id FROM user_badges
            WHERE user_id > $1 ORDER BY user_id LIMIT ${BATCH}`,
          [cursor],
        );
    if (rows.length === 0) break;

    for (const { user_id } of rows) {
      try {
        repaired += await redateBadges(user_id);
      } catch (err: any) {
        failed++;
        console.error(`[badge-dates] ${user_id} failed:`, err?.message ?? err);
      }
    }
    users += rows.length;
    cursor = rows[rows.length - 1].user_id;
    if (!onlyUserIds) await new Promise((r) => setTimeout(r, PAUSE_MS));
  }

  // A targeted (test) run never writes the global marker, and neither does a
  // run that left anyone behind.
  if (!onlyUserIds && failed === 0) {
    await client.query(
      `INSERT INTO maintenance_runs (name, completed_at, detail)
       VALUES ($1, NOW(), $2)
       ON CONFLICT (name) DO UPDATE SET completed_at = EXCLUDED.completed_at, detail = EXCLUDED.detail`,
      [BADGE_DATE_REPAIR, JSON.stringify({ users, repaired })],
    );
  }
  return { skipped: false, users, repaired, failed };
}

export async function repairBadgeEarnedDates(): Promise<void> {
  if (process.env.BADGE_DATE_REPAIR_DISABLED === "1") return;
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    statement_timeout: 0,
    query_timeout: 0,
  });
  try {
    await client.connect();
    const started = Date.now();
    const r = await runBadgeDateRepair(client);
    if (!r.skipped) {
      console.log(
        `[badge-dates] re-dated ${r.repaired} medal(s) over ${r.users} user(s), ${r.failed} failed, in ${Math.round((Date.now() - started) / 1000)}s`,
      );
    }
  } catch (err) {
    // Never take the server down for this; the next boot retries.
    console.error("[badge-dates] repair failed (will retry next boot):", err);
  } finally {
    await client.end().catch(() => {});
  }
}
