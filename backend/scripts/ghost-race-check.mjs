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

  await db.query(`DELETE FROM workouts WHERE user_id = $1`, [USER]);
  await db.query(`DELETE FROM users WHERE user_id = $1`, [USER]);

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
