/**
 * Cross-app duplicate detection: the FRAGMENT case.
 *
 * Reproduces the exact shape that reached production: Mile A Day tracked a
 * 1.84 mi walk in-app, Google Health independently wrote a 0.36 mi walk sitting
 * entirely inside that window, and the day counted 2.20 mi. The pair passes the
 * time-overlap test and FAILS the distance-agreement test
 * (|1.84 - 0.36| = 1.48 > max(0.1, 0.2 * 1.84) = 0.368), so agreement alone can
 * never see it.
 *
 * Usage: DATABASE_URL=... node scripts/dedupe-containment-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import { recomputeDuplicatesForDay } from "../dist/services/workoutService.js";

const db = PostgresService.getInstance();

/** Mirrors duplicateExclusionEnabled(), which isn't exported. */
function dedupeEnabledForTest() {
  const v = (process.env.WORKOUT_DEDUPE ?? "").toLowerCase();
  return !(v === "0" || v === "false" || v === "off");
}
const USER = "dedupe-check-user";
const DAY = "2026-08-06";

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`);
}

/** endsAt is an ISO string; duration in seconds. */
async function insert(id, { bundle, distance, endsAt, duration, route = false }) {
  await db.query(
    `INSERT INTO workouts
       (workout_id, user_id, distance, local_date, date, device_end_date,
        total_duration, workout_type, source_bundle_id, calories,
        timezone_offset)
     VALUES ($1, $2, $3, $4::date, $5::timestamptz, $5::timestamptz, $6,
             'walking', $7, 0, -14400)
     ON CONFLICT (workout_id) DO UPDATE
       SET distance = EXCLUDED.distance,
           device_end_date = EXCLUDED.device_end_date,
           total_duration = EXCLUDED.total_duration,
           source_bundle_id = EXCLUDED.source_bundle_id`,
    [id, USER, distance, DAY, endsAt, duration, bundle],
  );
  if (route) {
    await db.query(
      `INSERT INTO workout_routes (workout_id, route, point_count)
       VALUES ($1, '[]'::jsonb, 0) ON CONFLICT (workout_id) DO NOTHING`,
      [id],
    );
  }
}

async function cleanup() {
  await db.query(
    `DELETE FROM workout_routes WHERE workout_id IN
       (SELECT workout_id FROM workouts WHERE user_id = $1)`, [USER]);
  await db.query(`DELETE FROM workouts WHERE user_id = $1`, [USER]);
  await db.query(`DELETE FROM users WHERE user_id = $1`, [USER]);
}

async function main() {
  await cleanup();
  await db.query(
    `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
     VALUES ($1, $2, $3, $4, 'Dedupe', 'Check') ON CONFLICT DO NOTHING`,
    [USER, `sub-${USER}`, `${USER}@example.com`, USER],
  );

  // Mile A Day: 1.84 mi over 92:05, ending 19:00. Has a GPS route, which is
  // what makes it the preferred copy.
  await insert("mad-walk", {
    bundle: "com.mileaday.app",
    distance: 1.84,
    endsAt: `${DAY}T19:00:00.000Z`,
    duration: 5525,
    route: true,
  });
  // Google Health: 0.36 mi over 18:05, ending 18:50 — wholly inside the above.
  await insert("google-walk", {
    bundle: "com.google.health",
    distance: 0.36,
    endsAt: `${DAY}T18:50:00.000Z`,
    duration: 1085,
  });

  await recomputeDuplicatesForDay(USER, DAY);

  const rows = await db.query(
    `SELECT workout_id, duplicate_of FROM workouts WHERE user_id = $1 ORDER BY workout_id`,
    [USER],
  );
  const byId = Object.fromEntries(rows.map((r) => [r.workout_id, r.duplicate_of]));
  check("the fragment is marked a duplicate", byId["google-walk"], "mad-walk");
  // Survivorship: the copy with the route is the one that keeps counting.
  check("the full walk is NOT marked", byId["mad-walk"], null);

  // A genuinely separate second walk later the same day must survive. This is
  // the assertion that stops the rule eating real miles.
  await insert("evening-walk", {
    bundle: "com.google.health",
    distance: 0.9,
    endsAt: `${DAY}T21:30:00.000Z`,
    duration: 1800,
  });
  await recomputeDuplicatesForDay(USER, DAY);
  const [evening] = await db.query(
    `SELECT duplicate_of FROM workouts WHERE workout_id = 'evening-walk'`);
  check("a separate later walk is untouched", evening?.duplicate_of, null);

  // Same source = same app segmenting its own walk. Never paired: that's the
  // app's own business and UUID dedup already covers real repeats.
  await insert("mad-second", {
    bundle: "com.mileaday.app",
    distance: 0.2,
    endsAt: `${DAY}T18:40:00.000Z`,
    duration: 600,
  });
  await recomputeDuplicatesForDay(USER, DAY);
  const [sameSource] = await db.query(
    `SELECT duplicate_of FROM workouts WHERE workout_id = 'mad-second'`);
  check("same-source fragments are never paired", sameSource?.duplicate_of, null);

  // The kill switch's DIRECTION, same regression class as BUDDY_SESSIONS: a
  // pass that is inert unless someone remembers to set an env var is a pass
  // that does nothing in production.
  const saved = process.env.WORKOUT_DEDUPE;
  delete process.env.WORKOUT_DEDUPE;
  check("unset → exclusion is ON", dedupeEnabledForTest(), true);
  process.env.WORKOUT_DEDUPE = "false";
  check('"false" → exclusion is OFF', dedupeEnabledForTest(), false);
  if (saved === undefined) delete process.env.WORKOUT_DEDUPE;
  else process.env.WORKOUT_DEDUPE = saved;

  await cleanup();
  console.log(
    failures === 0
      ? "dedupe-containment-check: all assertions passed"
      : `dedupe-containment-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (e) => { console.error(e); await cleanup().catch(() => {}); process.exit(1); });
