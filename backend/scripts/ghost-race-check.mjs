/**
 * Ghost-race persistence check.
 *
 * Proves the three things the medal family depends on, against a real
 * migrated database:
 *   1. a winning workout's margin/target survive `uploadWorkouts`
 *   2. an implausible claim is dropped to NULL rather than stored
 *   3. a re-upload WITHOUT the fields (fullSync, recalibrate — neither reads
 *      HealthKit metadata) does not erase a win already recorded
 * plus the aggregate the ghost medals actually count.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/ghost-race-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import { uploadWorkouts } from "../dist/services/workoutService.js";
import {
  notifyGhostsBeaten,
  getGhostHistory,
} from "../dist/services/ghostService.js";

const db = PostgresService.getInstance();
const USER = "ghost-check-user";

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

function workout(id, extra = {}) {
  return {
    workoutId: id,
    distance: 1.2,
    localDate: "2026-08-01",
    date: "2026-08-01T12:00:00.000Z",
    timezoneOffset: -14400,
    workoutType: "running",
    deviceEndDate: "2026-08-01T12:30:00.000Z",
    calories: 120,
    totalDuration: 1800,
    movingSeconds: 1700,
    splits: [],
    ...extra,
  };
}

async function main() {
  await db.query(
    `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
     VALUES ($1, $2, $3, $4, 'Ghost', 'Check')
     ON CONFLICT (user_id) DO NOTHING`,
    [USER, `sub-${USER}`, `${USER}@example.com`, USER],
  );
  await db.query(`DELETE FROM workouts WHERE user_id = $1`, [USER]);

  // 1. A real win persists.
  await uploadWorkouts(USER, [
    workout("ghost-win", { ghostMarginSeconds: 14, ghostTargetSeconds: 542 }),
  ]);
  const [win] = await db.query(
    `SELECT ghost_margin_seconds AS m, ghost_target_seconds AS t
       FROM workouts WHERE workout_id = 'ghost-win'`,
  );
  check("win margin stored", Number(win?.m), 14);
  check("win target stored", Number(win?.t), 542);

  // 2. Implausible claims are dropped, not stored.
  await uploadWorkouts(USER, [
    // margin larger than the ghost it supposedly beat
    workout("ghost-absurd", {
      ghostMarginSeconds: 9999,
      ghostTargetSeconds: 542,
    }),
    // target outside GhostTarget.isPlausible (2:00…40:00)
    workout("ghost-short", { ghostMarginSeconds: 5, ghostTargetSeconds: 30 }),
  ]);
  const dropped = await db.query(
    `SELECT COUNT(*)::int AS n FROM workouts
      WHERE user_id = $1 AND workout_id IN ('ghost-absurd','ghost-short')
        AND ghost_margin_seconds IS NOT NULL`,
    [USER],
  );
  check("implausible claims dropped", dropped[0].n, 0);

  // 3. A re-upload that carries no ghost fields must NOT erase the win.
  await uploadWorkouts(USER, [workout("ghost-win")]);
  const [after] = await db.query(
    `SELECT ghost_margin_seconds AS m FROM workouts WHERE workout_id = 'ghost-win'`,
  );
  check("win survives a metadata-less re-upload", Number(after?.m), 14);

  // 4. The aggregate the medals count.
  await uploadWorkouts(USER, [
    workout("ghost-win-2", { ghostMarginSeconds: 48, ghostTargetSeconds: 700 }),
  ]);
  const [agg] = await db.query(
    `SELECT COUNT(*)::int AS count,
            COALESCE(MAX(ghost_margin_seconds), 0)::int AS best
       FROM workouts
      WHERE user_id = $1 AND deleted_at IS NULL
        AND ghost_margin_seconds IS NOT NULL`,
    [USER],
  );
  check("ghostsBeaten", agg.count, 2);
  check("bestGhostMargin", agg.best, 48);

  // A soft-deleted workout must stop counting.
  await db.query(
    `UPDATE workouts SET deleted_at = NOW() WHERE workout_id = 'ghost-win-2'`,
  );
  const [aggAfter] = await db.query(
    `SELECT COUNT(*)::int AS count FROM workouts
      WHERE user_id = $1 AND deleted_at IS NULL AND ghost_margin_seconds IS NOT NULL`,
    [USER],
  );
  check("deleted workout stops counting", aggAfter.count, 1);

  // ── Friend ghosts: whose ghost was beaten, and telling them once ──
  const FRIEND = "ghost-check-friend";
  await db.query(
    `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
     VALUES ($1, $2, $3, $4, 'Ghost', 'Friend')
     ON CONFLICT (user_id) DO NOTHING`,
    [FRIEND, `sub-${FRIEND}`, `${FRIEND}@example.com`, FRIEND],
  );
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
     ON CONFLICT (user_id, friend_id) DO NOTHING`,
    [USER, FRIEND],
  );

  await uploadWorkouts(USER, [
    workout("ghost-friend-win", {
      ghostMarginSeconds: 9,
      ghostTargetSeconds: 600,
      ghostFriendUserId: FRIEND,
    }),
  ]);
  const [friendRow] = await db.query(
    `SELECT ghost_friend_user_id AS f FROM workouts WHERE workout_id = 'ghost-friend-win'`,
  );
  check("friend id stored", friendRow?.f, FRIEND);

  // Same COALESCE protection as the margin: a fullSync re-upload carries no
  // HealthKit metadata and must not anonymize a recorded win.
  await uploadWorkouts(USER, [workout("ghost-friend-win")]);
  const [afterResync] = await db.query(
    `SELECT ghost_friend_user_id AS f FROM workouts WHERE workout_id = 'ghost-friend-win'`,
  );
  check("friend id survives a metadata-less re-upload", afterResync?.f, FRIEND);

  // The notify pass claims the row exactly once, so the constant re-uploads of
  // the same workout can never re-push.
  await notifyGhostsBeaten(USER, ["ghost-friend-win"]);
  const [claimed] = await db.query(
    `SELECT (ghost_notified_at IS NOT NULL) AS done FROM workouts
      WHERE workout_id = 'ghost-friend-win'`,
  );
  check("notify claims the row", claimed?.done, true);

  await db.query(
    `UPDATE workouts SET ghost_notified_at = NULL WHERE workout_id = 'ghost-friend-win'`,
  );
  // A workout naming someone who ISN'T a friend must not even be claimed —
  // the id is client-asserted, so the friendship is re-checked at notify time.
  await db.query(
    `UPDATE workouts SET ghost_friend_user_id = 'ghost-check-stranger'
      WHERE workout_id = 'ghost-friend-win'`,
  );
  await notifyGhostsBeaten(USER, ["ghost-friend-win"]);
  const [stranger] = await db.query(
    `SELECT (ghost_notified_at IS NOT NULL) AS done FROM workouts
      WHERE workout_id = 'ghost-friend-win'`,
  );
  check("a non-friend claim is never notified", stranger?.done, false);

  // ── Losses ──
  //
  // The margin is SIGNED and every completed race is stored. That makes
  // `IS NOT NULL` stop meaning "won", so each consequence gets an assertion.
  await db.query(
    `UPDATE workouts SET ghost_notified_at = NULL, ghost_friend_user_id = $1
      WHERE workout_id = 'ghost-friend-win'`,
    [FRIEND],
  );
  await uploadWorkouts(USER, [
    workout("ghost-loss", {
      ghostMarginSeconds: -7,
      ghostTargetSeconds: 600,
      ghostFriendUserId: FRIEND,
    }),
  ]);
  const [loss] = await db.query(
    `SELECT ghost_margin_seconds AS m FROM workouts WHERE workout_id = 'ghost-loss'`,
  );
  check("a loss is stored, signed", Number(loss?.m), -7);

  // ...and survives the same metadata-less re-upload a win does.
  await uploadWorkouts(USER, [workout("ghost-loss")]);
  const [lossAfter] = await db.query(
    `SELECT ghost_margin_seconds AS m FROM workouts WHERE workout_id = 'ghost-loss'`,
  );
  check("a loss survives a metadata-less re-upload", Number(lossAfter?.m), -7);

  // A loss must never be notified — that would tell someone their ghost was
  // caught when it wasn't.
  await notifyGhostsBeaten(USER, ["ghost-loss"]);
  const [lossNotified] = await db.query(
    `SELECT (ghost_notified_at IS NOT NULL) AS done FROM workouts
      WHERE workout_id = 'ghost-loss'`,
  );
  check("a loss is never notified", lossNotified?.done, false);

  // Medals count WINS. This is the subtle one: without `> 0` the MAX returns a
  // NEGATIVE for a user who has only ever lost, and COALESCE won't catch it.
  await db.query(`DELETE FROM workouts WHERE user_id = $1 AND workout_id <> 'ghost-loss'`, [USER]);
  const [onlyLosses] = await db.query(
    `SELECT COUNT(*)::int AS count,
            COALESCE(MAX(ghost_margin_seconds), 0)::int AS best
       FROM workouts
      WHERE user_id = $1 AND deleted_at IS NULL AND ghost_margin_seconds > 0`,
    [USER],
  );
  check("a loss does not count as a win", onlyLosses.count, 0);
  check("bestGhostMargin is 0, not negative", onlyLosses.best, 0);

  // History keeps the losses — the one surface that should.
  const history = await getGhostHistory(USER);
  check("history includes the loss", history.length, 1);
  check(
    "history reports the friend's name",
    history[0]?.friend_name,
    "Ghost",
  );

  // An implausible loss is still dropped, same as an implausible win.
  await uploadWorkouts(USER, [
    workout("ghost-loss-absurd", {
      ghostMarginSeconds: -99999,
      ghostTargetSeconds: 600,
    }),
  ]);
  const [absurdLoss] = await db.query(
    `SELECT ghost_margin_seconds AS m FROM workouts WHERE workout_id = 'ghost-loss-absurd'`,
  );
  check("an implausible loss is dropped", absurdLoss?.m, null);

  await db.query(
    `DELETE FROM friendships WHERE user_id = $1 OR friend_id = $1`,
    [FRIEND],
  );
  await db.query(`DELETE FROM workouts WHERE user_id = $1`, [USER]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [
    [USER, FRIEND],
  ]);

  console.log(
    failures === 0
      ? "ghost-race-check: all assertions passed"
      : `ghost-race-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
