/**
 * Flamey check — the server half of the Fun-dashboard mascot.
 *
 *   1. holiday date math across years (Easter, Thanksgiving, fixed dates);
 *   2. `PATCH /users/:id { dashboard_style }` validation + the friends-list
 *      projection carrying it;
 *   3. the additive `flamey` block on `GET /users/:id`: enabled only for a
 *      Fun target, and `{enabled:false}` to a stranger (it carries medals,
 *      which are friends-only);
 *   4. holiday medals through the REAL upload endpoint: awarded on a goal
 *      day, NOT on a sub-goal day (goal × tolerance, not a flat mile), NOT
 *      from a duplicate-excluded workout, silent for a backdated walk, and
 *      revoked when the only qualifying walk is deleted;
 *   5. the retroactive backfill: awards silently, idempotent, done-marker;
 *   6. the Flamey poke: 403 `flamey_unavailable` unless BOTH sides are Fun,
 *      200 with `source: "flamey"` on the same `friend_nudge` type, the same
 *      once-a-day cooldown as a plain nudge, and a plain nudge unchanged.
 *
 * Every failure here is silent in production (a medal nobody gets, a block
 * that reads "no Flamey"), so the assertions are memberships and deltas on
 * this script's own users, never global counts.
 *
 * Usage (same env as ci-smoke):  DATABASE_URL=... node scripts/flamey-check.mjs
 */
import express from "express";
import pg from "pg";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import userRoutes from "../dist/routes/usersRoutes.js";
import friendRoutes from "../dist/routes/friendshipsRoutes.js";
import workoutRoutes from "../dist/routes/workoutRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import {
  holidayKeyForLocalDate,
  easterMonthDay,
  thanksgivingDay,
  HOLIDAYS,
} from "../dist/services/holidays.js";
import { revokeUnearnedBadges, seedExtraBadges } from "../dist/services/badgeService.js";
import { runHolidayMedalBackfill } from "../dist/db/backfillHolidayMedals.js";
import { runBadgeDateRepair } from "../dist/db/repairBadgeEarnedDates.js";

const db = PostgresService.getInstance();

const FUN_A = "fl-fun-a"; // sender, Fun
const FUN_B = "fl-fun-b"; // friend of A, Fun — the Flamey target
const MODERN = "fl-modern"; // friend of A, Modern
const LEGACY = "fl-legacy"; // friend of A, NULL style (older build)
const STRANGER = "fl-stranger"; // Fun, not anyone's friend
const WALKER = "fl-walker"; // holiday medals via the sync path
const GOAL2 = "fl-goal2"; // goal 2 mi — a 1.5 mi holiday walk is short
const BACK = "fl-backfill"; // history seeded straight into SQL
const ALL = [FUN_A, FUN_B, MODERN, LEGACY, STRANGER, WALKER, GOAL2, BACK];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

async function cleanup() {
  const tables = [
    [`DELETE FROM user_badges WHERE user_id = ANY($1)`],
    [`DELETE FROM in_app_notifications WHERE user_id = ANY($1)`],
    [`DELETE FROM notification_log WHERE user_id = ANY($1)`],
    [`DELETE FROM pending_notifications WHERE user_id = ANY($1)`],
    [`DELETE FROM friend_nudge_log WHERE sender_id = ANY($1) OR target_id = ANY($1)`],
    [`DELETE FROM friendships WHERE user_id = ANY($1) OR friend_id = ANY($1)`],
    [`DELETE FROM notification_settings WHERE user_id = ANY($1)`],
    [`DELETE FROM workout_splits WHERE workout_id IN (SELECT workout_id FROM workouts WHERE user_id = ANY($1))`],
    [`DELETE FROM workout_routes WHERE workout_id IN (SELECT workout_id FROM workouts WHERE user_id = ANY($1))`],
  ];
  for (const [q] of tables) await db.query(q, [ALL]).catch(() => {});
  // Anything else keyed on these users from the upload side effects
  // (challenge completions, streak rows, feed notifications, …).
  const fkTables = await db.query(
    `SELECT DISTINCT tc.table_name
       FROM information_schema.table_constraints tc
       JOIN information_schema.constraint_column_usage ccu
         ON ccu.constraint_name = tc.constraint_name
      WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'users'
        AND ccu.column_name = 'user_id'`,
  );
  for (const { table_name } of fkTables) {
    const cols = await db.query(
      `SELECT column_name FROM information_schema.columns
        WHERE table_name = $1 AND column_name IN ('user_id','sender_id','target_id','friend_id')`,
      [table_name],
    );
    for (const { column_name } of cols) {
      await db.query(`DELETE FROM ${table_name} WHERE ${column_name} = ANY($1)`, [ALL]).catch(() => {});
    }
  }
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

async function befriend(a, b) {
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted')`,
    [a, b],
  );
}

const app = express();
app.use(express.json({ limit: "2mb" }));
app.use(authenticateToken);
app.use("/users", userRoutes);
app.use("/friends", friendRoutes);
app.use("/workouts", workoutRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

async function call(method, path, userId, body) {
  const token = await generateAccessToken(userId);
  const res = await fetch(base + path, {
    method,
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {}
  return { status: res.status, json };
}

function workout(id, localDate, distance, extra = {}) {
  return {
    workoutId: id,
    distance,
    localDate,
    date: `${localDate}T12:00:00.000Z`,
    timezoneOffset: 0,
    workoutType: "walking",
    deviceEndDate: `${localDate}T12:30:00.000Z`,
    calories: 100,
    totalDuration: 1800,
    splits: [],
    ...extra,
  };
}

const badgesOf = async (userId) =>
  (
    await db.query(`SELECT badge_id FROM user_badges WHERE user_id = $1 AND badge_id LIKE 'holiday\\_%' ORDER BY badge_id`, [userId])
  ).map((r) => r.badge_id);
const inboxCount = async (userId, type) =>
  (await db.query(`SELECT COUNT(*)::int AS n FROM in_app_notifications WHERE user_id = $1 AND type = $2`, [userId, type]))[0].n;

try {
  await cleanup();
  await seedExtraBadges();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, first_name) VALUES ($1::text, $1::text, $1::text, $1::text || '@example.com', 'T')`,
      [id],
    );
  }
  await db.query(`UPDATE users SET goal_miles = 2 WHERE user_id = $1`, [GOAL2]);
  await befriend(FUN_A, FUN_B);
  await befriend(FUN_A, MODERN);
  await befriend(FUN_A, LEGACY);

  // ── 1. Holiday date math.
  const md = (y) => easterMonthDay(y).join("-");
  check("Easter 2025", md(2025), "4-20");
  check("Easter 2026", md(2026), "4-5");
  check("Easter 2027", md(2027), "3-28");
  check("Easter 2024", md(2024), "3-31");
  check("Easter 2038 (latest-ish)", md(2038), "4-25");
  check("Thanksgiving 2026", thanksgivingDay(2026), 26);
  check("Thanksgiving 2027", thanksgivingDay(2027), 25);
  check("Thanksgiving 2025", thanksgivingDay(2025), 27);
  check("2026-04-05 is easter", holidayKeyForLocalDate("2026-04-05"), "easter");
  check("2025-04-20 is easter", holidayKeyForLocalDate("2025-04-20"), "easter");
  check("2026-04-20 is NOT easter", holidayKeyForLocalDate("2026-04-20"), null);
  check("2026-11-26 is thanksgiving", holidayKeyForLocalDate("2026-11-26"), "thanksgiving");
  check("2027-11-25 is thanksgiving", holidayKeyForLocalDate("2027-11-25"), "thanksgiving");
  check("2026-11-27 is NOT thanksgiving", holidayKeyForLocalDate("2026-11-27"), null);
  check("fixed dates", ["2026-01-01", "2026-02-14", "2026-03-17", "2026-07-04", "2026-10-31", "2026-12-24", "2026-12-25", "2026-12-31"].map(holidayKeyForLocalDate), [
    "new_years_day", "valentines_day", "st_patricks_day", "independence_day", "halloween", "christmas_eve", "christmas", "new_years_eve",
  ]);
  check("ordinary day", holidayKeyForLocalDate("2026-09-24"), null);
  check("garbage", holidayKeyForLocalDate("10/31/2026"), null);
  check("ten holidays", HOLIDAYS.length, 10);

  // ── 2. dashboard_style PATCH + friends-list projection.
  let r = await call("PATCH", `/users/${FUN_A}`, FUN_A, { dashboard_style: "retro" });
  check("unknown style → 400", [r.status, r.json?.error], [400, "invalid_dashboard_style"]);
  r = await call("PATCH", `/users/${FUN_A}`, FUN_A, { dashboard_style: null });
  check("null style → 400", [r.status, r.json?.error], [400, "invalid_dashboard_style"]);
  r = await call("PATCH", `/users/${FUN_A}`, FUN_A, { dashboard_style: 5 });
  check("non-string style → 400", r.status, 400);
  r = await call("PATCH", `/users/${FUN_B}`, FUN_A, { dashboard_style: "fun" });
  check("someone else's row → 403", r.status, 403);
  r = await call("PATCH", `/users/${FUN_A}`, FUN_A, { dashboard_style: "fun" });
  check("fun → 200 + echoed", [r.status, r.json?.dashboard_style], [200, "fun"]);
  for (const [u, s] of [[FUN_B, "fun"], [MODERN, "modern"], [STRANGER, "fun"]]) {
    r = await call("PATCH", `/users/${u}`, u, { dashboard_style: s });
    check(`${u} → ${s}`, r.json?.dashboard_style, s);
  }
  r = await call("GET", `/friends/${FUN_A}`, FUN_A);
  const styles = Object.fromEntries((r.json ?? []).map((f) => [f.user_id, f.dashboard_style]));
  check("friends list carries dashboard_style", [styles[FUN_B], styles[MODERN], styles[LEGACY]], ["fun", "modern", null]);

  // ── 3. The flamey block on GET /users/:id.
  await db.query(
    `UPDATE users SET longest_streak = 412, created_at = '2025-06-13T12:00:00Z' WHERE user_id = $1`,
    [FUN_B],
  );
  await db.query(
    `INSERT INTO user_badges (user_id, badge_id) VALUES ($1, 'holiday_christmas'), ($1, 'holiday_halloween')`,
    [FUN_B],
  );
  r = await call("GET", `/users/${FUN_B}`, FUN_A);
  console.log("      sample GET /users/:id flamey (friend, fun):", JSON.stringify(r.json?.flamey));
  check("friend + fun → full block", r.json?.flamey, {
    enabled: true,
    longest_streak: 412,
    holiday_keys: ["halloween", "christmas"],
    signup_date: "2025-06-13",
    look: null, // Flamey's Closet: never saved ⇒ auto
    owned_item_ids: ["classic", "santa_hat", "pumpkin_suit", "classic_bubble"],
    name: null, // Flamey's name: never set ⇒ "Flamey" (client default)
  });
  check("…and the row itself is still there", r.json?.user_id, FUN_B);
  r = await call("GET", `/users/${FUN_B}`, FUN_B);
  check("self sees own block", r.json?.flamey?.enabled, true);
  r = await call("GET", `/users/${FUN_B}`, STRANGER);
  console.log("      sample GET /users/:id flamey (stranger):", JSON.stringify(r.json?.flamey));
  check("stranger → disabled (medals are friends-only)", r.json?.flamey, { enabled: false });
  r = await call("GET", `/users/${MODERN}`, FUN_A);
  check("modern target → disabled", r.json?.flamey, { enabled: false });
  r = await call("GET", `/users/${LEGACY}`, FUN_A);
  check("NULL-style target → disabled", r.json?.flamey, { enabled: false });
  // signup_date is the user's LOCAL date when an offset is known.
  await db.query(`UPDATE users SET created_at = '2025-06-13T03:00:00Z' WHERE user_id = $1`, [FUN_B]);
  await db.query(
    `INSERT INTO notification_settings (user_id, timezone_offset_minutes) VALUES ($1, -420)
     ON CONFLICT (user_id) DO UPDATE SET timezone_offset_minutes = EXCLUDED.timezone_offset_minutes`,
    [FUN_B],
  );
  r = await call("GET", `/users/${FUN_B}`, FUN_A);
  check("signup_date in the user's own timezone", r.json?.flamey?.signup_date, "2025-06-12");

  // ── 4. Holiday medals through the real upload path.
  const walkerPushesBefore = await inboxCount(WALKER, "badge_earned");
  r = await call("POST", `/workouts/${WALKER}/upload`, WALKER, [workout("fl-w-hallo", "2025-10-31", 1.0)]);
  check("upload 200", r.status, 200);
  check("halloween goal walk → medal", await badgesOf(WALKER), ["holiday_halloween"]);
  const trig = (await db.query(`SELECT triggering_workout_id FROM user_badges WHERE user_id = $1 AND badge_id = 'holiday_halloween'`, [WALKER]))[0];
  check("…attributed to that walk", trig?.triggering_workout_id, "fl-w-hallo");
  check("…in the upload response", (r.json?.newlyEarnedBadges ?? []).map((b) => b.badgeId).includes("holiday_halloween"), true);
  check("…silently (a backdated walk never pushes)", (await inboxCount(WALKER, "badge_earned")) - walkerPushesBefore, 0);

  await call("POST", `/workouts/${WALKER}/upload`, WALKER, [workout("fl-w-xmas", "2025-12-25", 0.5)]);
  check("sub-goal christmas walk → nothing", (await badgesOf(WALKER)).includes("holiday_christmas"), false);
  // Topping the day up past the line in a second walk earns it.
  await call("POST", `/workouts/${WALKER}/upload`, WALKER, [workout("fl-w-xmas2", "2025-12-25", 0.46, { deviceEndDate: "2025-12-25T18:00:00.000Z" })]);
  check("two walks summing to 0.96 → medal (tolerance)", (await badgesOf(WALKER)).includes("holiday_christmas"), true);

  r = await call("POST", `/workouts/${GOAL2}/upload`, GOAL2, [workout("fl-g-july", "2025-07-04", 1.5)]);
  check("1.5 mi on a 2 mi goal → nothing", await badgesOf(GOAL2), []);
  await call("POST", `/workouts/${GOAL2}/upload`, GOAL2, [workout("fl-g-july2", "2025-07-04", 0.5, { deviceEndDate: "2025-07-04T19:00:00.000Z" })]);
  check("2.0 mi on a 2 mi goal → medal", await badgesOf(GOAL2), ["holiday_independence_day"]);

  // A Strava twin excluded as a duplicate must not earn it. The upsert resets
  // exclusion_reason, so mark it after the upload and re-run the evaluation
  // the way the next sync would (re-uploading the same id is what the phone
  // does — but that would reset the mark, so evaluate directly).
  const { evaluateWorkoutRewards } = await import("../dist/services/badgeService.js");
  await call("POST", `/workouts/${WALKER}/upload`, WALKER, [workout("fl-w-easter", "2026-04-05", 0.2)]);
  await db.query(`UPDATE workouts SET distance = 1.2, exclusion_reason = 'duplicate_source' WHERE workout_id = 'fl-w-easter'`);
  await evaluateWorkoutRewards(WALKER, ["fl-w-easter"]);
  check("duplicate-excluded easter walk → nothing", (await badgesOf(WALKER)).includes("holiday_easter"), false);

  // Revocation: delete the only halloween walk.
  await db.query(`UPDATE workouts SET deleted_at = NOW() WHERE workout_id = 'fl-w-hallo'`);
  const revoked = await revokeUnearnedBadges(WALKER);
  check("deleting the only halloween walk revokes it", revoked.includes("holiday_halloween"), true);
  check("…and keeps christmas", (await badgesOf(WALKER)).includes("holiday_christmas"), true);

  // ── 5. The retroactive backfill.
  const seedWalk = (id, day, dist, excl = null) =>
    db.query(
      `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset, workout_type,
                             device_end_date, calories, total_duration, exclusion_reason)
       VALUES ($1, $2, $3, $4::date, $4::date, 0, 'walking', ($4 || 'T12:00:00Z')::timestamptz, 0, 1800, $5)`,
      [id, BACK, dist, day, excl],
    );
  await seedWalk("fl-b-xmas", "2024-12-25", 1.0);
  await seedWalk("fl-b-pat", "2024-03-17", 0.4); // sub-goal
  await seedWalk("fl-b-ny", "2024-01-01", 1.5, "duplicate_source"); // excluded
  await seedWalk("fl-b-tg", "2023-11-23", 0.97); // Thanksgiving 2023, inside tolerance
  const backInboxBefore = (await db.query(`SELECT COUNT(*)::int AS n FROM in_app_notifications WHERE user_id = $1`, [BACK]))[0].n;
  const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await client.connect();
  try {
    const first = await runHolidayMedalBackfill(client, { force: true });
    check("backfill ran", first.skipped, false);
    check("backfill awards exactly the goal days", await badgesOf(BACK), ["holiday_christmas", "holiday_thanksgiving"]);
    const snap = (await db.query(`SELECT progress_snapshot, triggering_workout_id, is_new FROM user_badges WHERE user_id = $1 AND badge_id = 'holiday_christmas'`, [BACK]))[0];
    check("…with the day recorded", [snap?.progress_snapshot?.holiday_date, snap?.triggering_workout_id, snap?.is_new], ["2024-12-25", "fl-b-xmas", true]);
    const earnedAt = async (u, badge) =>
      (await db.query(
        `SELECT to_char(earned_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') AS at FROM user_badges WHERE user_id = $1 AND badge_id = $2`,
        [u, badge],
      ))[0]?.at;
    check("…dated by the walk, not the run", await earnedAt(BACK, "holiday_christmas"), "2024-12-25T12:00:00");
    check("…silently (no inbox row, no push)", (await db.query(`SELECT COUNT(*)::int AS n FROM in_app_notifications WHERE user_id = $1`, [BACK]))[0].n - backInboxBefore, 0);
    const rowsBefore = (await db.query(`SELECT COUNT(*)::int AS n FROM user_badges WHERE user_id = ANY($1)`, [ALL]))[0].n;
    await runHolidayMedalBackfill(client, { force: true });
    const rowsAfter = (await db.query(`SELECT COUNT(*)::int AS n FROM user_badges WHERE user_id = ANY($1)`, [ALL]))[0].n;
    check("re-run is idempotent (no new rows for our users)", rowsAfter - rowsBefore, 0);
    const third = await runHolidayMedalBackfill(client);
    check("done-marker: next boot skips", third.skipped, true);

    // The date repair: rows the first backfill wrote at the deploy instant go
    // back on the walk's day; a live award (synced the same day) is untouched.
    await db.query(`UPDATE user_badges SET earned_at = NOW() WHERE user_id = $1 AND badge_id LIKE 'holiday\\_%'`, [BACK]);
    await db.query(
      `UPDATE user_badges SET earned_at = ($2 || 'T13:00:00Z')::timestamptz
       WHERE user_id = $1 AND badge_id = 'holiday_thanksgiving'`,
      [BACK, "2023-11-23"],
    );
    const fixed = await runBadgeDateRepair(client, { force: true, onlyUserIds: [BACK] });
    check("date repair ran", fixed.skipped, false);
    check("…re-dates a deploy-stamped medal to its walk", await earnedAt(BACK, "holiday_christmas"), "2024-12-25T12:00:00");
    check("…leaves a same-day award alone", await earnedAt(BACK, "holiday_thanksgiving"), "2023-11-23T13:00:00");
    const stamped = (await db.query(`SELECT progress_snapshot FROM user_badges WHERE user_id = $1 AND badge_id = 'holiday_christmas'`, [BACK]))[0];
    check("…keeps the replaced date on the row", typeof stamped?.progress_snapshot?.stamped_at, "string");
    await runBadgeDateRepair(client, { force: true, onlyUserIds: [BACK] });
    check("…and a re-run finds nothing for our user", await earnedAt(BACK, "holiday_christmas"), "2024-12-25T12:00:00");
  } finally {
    await client.end();
  }

  // ── 6. The Flamey poke.
  const nudgeInbox = async (u) =>
    db.query(`SELECT title, body, data FROM in_app_notifications WHERE user_id = $1 AND type = 'friend_nudge' ORDER BY created_at`, [u]);
  r = await call("POST", `/friends/${MODERN}/nudge`, FUN_A, { source: "flamey" });
  console.log("      sample flamey poke to a Modern friend:", r.status, JSON.stringify(r.json));
  check("recipient Modern → 403 flamey_unavailable", [r.status, r.json], [403, { error: "flamey_unavailable" }]);
  r = await call("POST", `/friends/${LEGACY}/nudge`, FUN_A, { source: "flamey" });
  check("recipient NULL-style → 403", r.status, 403);
  r = await call("POST", `/friends/${FUN_A}/nudge`, MODERN, { source: "flamey" });
  check("sender Modern → 403", [r.status, r.json?.error], [403, "flamey_unavailable"]);
  check("…a refused poke logs no nudge", (await db.query(`SELECT COUNT(*)::int AS n FROM friend_nudge_log WHERE sender_id = ANY($1)`, [ALL]))[0].n, 0);
  r = await call("POST", `/friends/${STRANGER}/nudge`, FUN_A, { source: "flamey" });
  check("both Fun but not friends → the ordinary friendship refusal", r.status, 400);

  r = await call("POST", `/friends/${FUN_B}/nudge`, FUN_A, { source: "flamey" });
  console.log("      sample flamey poke, both Fun:", r.status, JSON.stringify(r.json));
  check("both Fun → 200", r.status, 200);
  const pokes = await nudgeInbox(FUN_B);
  console.log("      sample inbox row:", JSON.stringify(pokes[0]));
  check("one friend_nudge row", pokes.length, 1);
  check("…source flamey, string-valued", [pokes[0]?.data?.source, pokes[0]?.data?.user_id, Object.values(pokes[0]?.data ?? {}).every((v) => typeof v === "string")], ["flamey", FUN_A, true]);
  check("…Flamey copy", pokes[0]?.title, "🔥 T poked your Flamey".replace("T", FUN_A));
  r = await call("POST", `/friends/${FUN_B}/nudge`, FUN_A, { source: "flamey" });
  check("same cooldown: second poke today → 429", r.status, 429);
  r = await call("POST", `/friends/${FUN_B}/nudge`, FUN_A);
  check("…and a plain nudge shares it → 429", r.status, 429);

  // A plain nudge is byte-for-byte the old one.
  r = await call("POST", `/friends/${MODERN}/nudge`, FUN_A);
  check("plain nudge to Modern → 200", [r.status, r.json], [200, { message: "Nudge sent" }]);
  const plain = await nudgeInbox(MODERN);
  check("…old copy + data, no source", [plain[0]?.title, plain[0]?.data], ["Time to lace up!", { user_id: FUN_A }]);
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch((e) => console.error("cleanup failed:", e.message));
  server.close();
  await db.close?.();
}

if (failures) {
  console.error(`\nflamey-check: ${failures} failure(s)`);
  process.exit(1);
}
console.log("\nflamey-check: all passed");
process.exit(0);
