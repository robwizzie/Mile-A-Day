import { Client } from "pg";
import { STREAK_QUALIFYING_STEPS, computeStreakEras } from "../services/streakFeatureCore.js";
import {
  refreshCurrentStreak,
  ratchetLongestStreak,
} from "../services/leaderboardService.js";
import { recalibrateBadges } from "../services/badgeService.js";
import { refundEarnedCoverage } from "../services/streakFeatureService.js";
import { getUserLocalToday } from "../services/workoutService.js";

/**
 * One-time re-count for "1 mile OR 10,000 steps": every user who already has
 * a 10k-step day on file gets their streak judged again with those days in.
 *
 * The rule change itself is live the moment the code is (every walk reads
 * `stepGoalDaysSql`), but three stored things only move when something
 * re-computes them, and for a user who doesn't upload a workout soon that
 * could be never:
 *   - `users.current_streak` — a run that steps now carry, or that a steps
 *     day in its past now joins to an older one;
 *   - `users.longest_streak` — two old runs a steps day bridges, which no
 *     current-streak write would ever see;
 *   - streak medals those longer runs earn.
 * Plus any token spent on a day the steps already covered goes back
 * (refundEarnedCoverage — its own window bounds how far back).
 *
 * Same contract as backfillRetroBadges: post-listen, not awaited, never takes
 * the server down, done-marker in `maintenance_runs` written only after the
 * LAST batch, idempotent and resumable (every write is a refresh, a
 * GREATEST, or an award-only insert). Medals go in SILENTLY (the retro-sweep
 * path) — a deploy-time burst of "Medal Unlocked" for days months ago is what
 * the push rules exist to stop.
 *
 * Step history older than the server's (it starts April 2026) arrives later
 * from each phone through the batch endpoint, which does the same per user.
 */
export const STEP_STREAKS_BACKFILL = "step_streaks_v1";
const BATCH = 100;
const PAUSE_MS = 250;

/** Exported for scripts/steps-streak-check.mjs; the server calls the wrapper. */
export async function runStepStreakBackfill(
  client: Client,
  {
    force = false,
    onlyUserIds,
  }: { force?: boolean; onlyUserIds?: string[] } = {},
): Promise<{ skipped: boolean; users: number; changed: number; failed: number }> {
  if (!force) {
    const done = await client.query(
      `SELECT 1 FROM maintenance_runs WHERE name = $1`,
      [STEP_STREAKS_BACKFILL],
    );
    if (done.rowCount) return { skipped: true, users: 0, changed: 0, failed: 0 };
  }

  let users = 0;
  let changed = 0;
  let failed = 0;
  let cursor = "";
  for (;;) {
    const { rows } = await client.query<{ user_id: string; before: number }>(
      `SELECT u.user_id, u.current_streak AS before
         FROM users u
        WHERE u.user_id > $1
          AND ($2::text[] IS NULL OR u.user_id = ANY($2::text[]))
          AND EXISTS (SELECT 1 FROM daily_steps ds
                       WHERE ds.user_id = u.user_id
                         AND ds.steps >= ${STREAK_QUALIFYING_STEPS})
        ORDER BY u.user_id
        LIMIT ${BATCH}`,
      [cursor, onlyUserIds ?? null],
    );
    if (rows.length === 0) break;

    for (const { user_id, before } of rows) {
      try {
        const after = await refreshCurrentStreak(user_id);
        if (after !== Number(before)) changed++;
        const { longest } = await computeStreakEras(
          user_id,
          await getUserLocalToday(user_id),
        );
        await ratchetLongestStreak(user_id, longest);
        await recalibrateBadges(user_id, "retro_sweep");
        await refundEarnedCoverage(user_id);
      } catch (err: any) {
        // One user's bad row must not stall everyone behind them; the next
        // steps upload re-runs the same steps for them.
        failed++;
        console.error(`[step-streaks] ${user_id} failed:`, err?.message ?? err);
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
      [STEP_STREAKS_BACKFILL, JSON.stringify({ users, changed, failed })],
    );
  }
  return { skipped: false, users, changed, failed };
}

export async function backfillStepStreaks(): Promise<void> {
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    statement_timeout: 0,
    query_timeout: 0,
  });
  try {
    await client.connect();
    const started = Date.now();
    const r = await runStepStreakBackfill(client);
    if (!r.skipped) {
      console.log(
        `[step-streaks] re-count done — ${r.changed} streak(s) changed over ${r.users} user(s), ${r.failed} failed, in ${Math.round((Date.now() - started) / 1000)}s`,
      );
    }
  } catch (err) {
    // Never take the server down for this; the next boot retries.
    console.error("[step-streaks] re-count failed (will retry next boot):", err);
  } finally {
    await client.end().catch(() => {});
  }
}
