/**
 * Buddy invite candidates: the picker's "who do I actually walk with / who
 * still uses the app" fields (`getInviteCandidates`).
 *
 *   1. `walks_together` counts only walks BOTH of you finished in a completed
 *      session (the `getBuddyPartners` rule) and drops one you hid.
 *   2. `active_days_ago` is days since their latest COUNTED workout: 0 for
 *      today, a deleted workout doesn't count, never-worked-out is null.
 *   3. A friend with `workout_visibility = 'private'` reads null, the same as
 *      never: the picker must not leak what their profile hides.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-candidates-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import { getInviteCandidates } from "../dist/services/buddySessionService.js";

const db = PostgresService.getInstance();

const ME = "buddy-cand-me";
const PAL = "buddy-cand-pal"; // walked with twice, active today
const QUIET = "buddy-cand-quiet"; // last workout 9 days ago, a newer one deleted
const SHY = "buddy-cand-shy"; // private workouts
const NEW = "buddy-cand-new"; // never worked out
const ALL = [ME, PAL, QUIET, SHY, NEW];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

async function cleanup() {
  await db.query(
    `DELETE FROM buddy_session_participants WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_sessions WHERE host_user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name, buddy_enrolled_at)
       VALUES ($1, $2, $3, $4, $5, 'Cand', NOW())
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  for (const a of ALL) {
    for (const b of ALL) {
      if (a === b) continue;
      await db.query(
        `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
         ON CONFLICT (user_id, friend_id) DO NOTHING`,
        [a, b],
      );
    }
  }
}

let w = 0;
async function workout(userId, daysAgo, { deleted = false } = {}) {
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration, deleted_at, source)
     VALUES ($1, $2, 1.1, CURRENT_DATE - $3::int, CURRENT_DATE - $3::int, 0, 'walking',
             (CURRENT_DATE - $3::int) + INTERVAL '1 hour', 100, 900,
             CASE WHEN $4::boolean THEN NOW() ELSE NULL END, 'healthkit')`,
    [`cand-w-${++w}`, userId, daysAgo, deleted],
  );
}

let sessionN = 0;
/** A walk ME and `friendId` were on, with each one's final status. */
async function walk(
  friendId,
  {
    sessionStatus = "completed",
    meStatus = "finished",
    themStatus = "finished",
    hidden = false,
  } = {},
) {
  const id = `cand-s-${++sessionN}`.padEnd(12, "x");
  await db.query(
    `INSERT INTO buddy_sessions (id, join_code, host_user_id, mode, activity_type, status, origin, local_date, started_at, created_at)
     VALUES ($1, $2, $3, 'together', 'walking', $4, 'invite', CURRENT_DATE - 1, NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day')`,
    [id, `C${sessionN}`.padEnd(6, "0"), ME, sessionStatus],
  );
  await db.query(
    `INSERT INTO buddy_session_participants (session_id, user_id, status, hidden_at)
     VALUES ($1, $2, $3, CASE WHEN $4::boolean THEN NOW() ELSE NULL END),
            ($1, $5, $6, NULL)`,
    [id, ME, meStatus, hidden, friendId, themStatus],
  );
}

async function main() {
  await cleanup();
  await seed();

  await workout(PAL, 0);
  await workout(QUIET, 9);
  await workout(QUIET, 1, { deleted: true });
  await workout(SHY, 0);
  await db.query(
    `INSERT INTO notification_settings (user_id, workout_visibility) VALUES ($1, 'private')
     ON CONFLICT (user_id) DO UPDATE SET workout_visibility = 'private'`,
    [SHY],
  );

  await walk(PAL);
  await walk(PAL);
  await walk(PAL, { themStatus: "left" }); // they didn't finish: not together
  await walk(PAL, { sessionStatus: "cancelled" }); // never happened
  await walk(QUIET, { hidden: true }); // I hid it from my archive

  const rows = await getInviteCandidates(ME);
  const by = (id) => rows.find((r) => r.user_id === id);

  check("every friend is a candidate", rows.length, 4);
  check("two finished walks together", by(PAL)?.walks_together, 2);
  check(
    "last walk together is a date",
    typeof by(PAL)?.last_walk_together,
    "string",
  );
  check("a hidden walk doesn't count", by(QUIET)?.walks_together, 0);
  check("never walked with = 0", by(NEW)?.walks_together, 0);
  check("worked out today = 0 days ago", by(PAL)?.active_days_ago, 0);
  check("a deleted workout doesn't count", by(QUIET)?.active_days_ago, 9);
  check("private workouts read null", by(SHY)?.active_days_ago, null);
  check("never worked out reads null", by(NEW)?.active_days_ago, null);

  await cleanup();
  console.log(
    failures === 0
      ? "buddy-candidates-check: all assertions passed"
      : `buddy-candidates-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
