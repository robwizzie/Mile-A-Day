import { Client } from "pg";
import { recalibrateBadges, seedExtraBadges } from "../services/badgeService.js";

/**
 * One-time retroactive medal sweep: every user gets exactly what Recalibrate
 * would give them (recalibrateBadges — ALL categories judged over the whole
 * history), because medals used to be judged on current state in places (the
 * streak ladder read the CURRENT run, so a broken 400-day streak never held
 * streak_365; the nudge medals counted a log pruned after 7 days) and the
 * holiday rule only ever looked at the days an upload touched.
 *
 * Same contract as backfillHolidayMedals: post-listen, not awaited, never
 * takes the server down, done-marker in `maintenance_runs` written only after
 * the LAST batch (every later boot is one SELECT), idempotent and resumable
 * — an interrupted run starts over next boot and re-awards nothing, since
 * recalibrateBadges only inserts what's missing (ON CONFLICT DO NOTHING).
 *
 * Bounded for prod: the dedicated no-timeout client does the paging and the
 * marker; each USER is then judged by the one evaluator every other path
 * uses (deliberately — a set-based rewrite of fifteen aggregates would be a
 * second answer to "has this person earned X?" that could disagree with the
 * live one). Every statement in it is scoped to that one user's rows, users
 * run strictly one at a time (one pool connection, ever), and batches pause
 * between them so live traffic always gets the pool first.
 *
 * AWARD-ONLY and SILENT: rows go straight into user_badges with no push and
 * no inbox row (`is_new` stays at its default TRUE — the in-app "new" dot).
 * A deploy-time burst of "Medal Unlocked" across the whole user base for
 * things done months ago is exactly the spam the push rules exist to stop.
 *
 * Grow what the evaluator can see (a new category, a new data source) ⇒ bump
 * the marker name so the sweep runs again.
 */
export const RETRO_BADGES_BACKFILL = "badge_retro_v1";
const BATCH = 100;
const PAUSE_MS = 250;

/** Exported for scripts/badge-recalibrate-check.mjs; the server calls the wrapper. */
export async function runRetroBadgeBackfill(
  client: Client,
  {
    force = false,
    onlyUserIds,
  }: { force?: boolean; onlyUserIds?: string[] } = {},
): Promise<{ skipped: boolean; users: number; awarded: number; failed: number }> {
  if (!force) {
    const done = await client.query(
      `SELECT 1 FROM maintenance_runs WHERE name = $1`,
      [RETRO_BADGES_BACKFILL],
    );
    if (done.rowCount) return { skipped: true, users: 0, awarded: 0, failed: 0 };
  }

  // The v2/holiday catalog rows must exist before anything can reference
  // them (FK). Idempotent; the boot seed is fire-and-forget, so don't race it.
  await seedExtraBadges();

  let users = 0;
  let awarded = 0;
  let failed = 0;
  let cursor = "";
  for (;;) {
    const { rows } = onlyUserIds
      ? await client.query<{ user_id: string }>(
          `SELECT user_id FROM users WHERE user_id > $1 AND user_id = ANY($2::text[])
           ORDER BY user_id LIMIT ${BATCH}`,
          [cursor, onlyUserIds],
        )
      : await client.query<{ user_id: string }>(
          `SELECT user_id FROM users WHERE user_id > $1 ORDER BY user_id LIMIT ${BATCH}`,
          [cursor],
        );
    if (rows.length === 0) break;

    for (const { user_id } of rows) {
      try {
        awarded += (await recalibrateBadges(user_id, "retro_sweep")).length;
      } catch (err: any) {
        // One user's bad row must not stall everyone behind them; they are
        // simply retried on the next Recalibrate or by a bumped marker.
        failed++;
        console.error(
          `[retro-badges] ${user_id} failed:`,
          err?.message ?? err,
        );
      }
    }
    users += rows.length;
    cursor = rows[rows.length - 1].user_id;
    if (!onlyUserIds) await new Promise((r) => setTimeout(r, PAUSE_MS));
  }

  // A targeted (test) run never writes the global marker.
  if (!onlyUserIds) {
    await client.query(
      `INSERT INTO maintenance_runs (name, completed_at, detail)
       VALUES ($1, NOW(), $2)
       ON CONFLICT (name) DO UPDATE SET completed_at = EXCLUDED.completed_at, detail = EXCLUDED.detail`,
      [RETRO_BADGES_BACKFILL, JSON.stringify({ users, awarded, failed })],
    );
  }
  return { skipped: false, users, awarded, failed };
}

export async function backfillRetroBadges(): Promise<void> {
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    statement_timeout: 0,
    query_timeout: 0,
  });
  try {
    await client.connect();
    const started = Date.now();
    const r = await runRetroBadgeBackfill(client);
    if (!r.skipped) {
      console.log(
        `[retro-badges] sweep done — ${r.awarded} medal(s) over ${r.users} user(s), ${r.failed} failed, in ${Math.round((Date.now() - started) / 1000)}s`,
      );
    }
  } catch (err) {
    // Never take the server down for this; the next boot retries.
    console.error("[retro-badges] sweep failed (will retry next boot):", err);
  } finally {
    await client.end().catch(() => {});
  }
}
