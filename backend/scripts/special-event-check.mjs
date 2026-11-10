/**
 * Special events check (Champ 5K Day).
 *
 * The medal is permanent and unlocks Flamey items, so the rule that grants it
 * is pinned on a real migrated database:
 *
 *   1. Every counted, device-measured walk and run ON the event's local day
 *      adds up; ~3.0 mi (3.1 × the daily-goal leeway) earns it.
 *   2. Short of that, another day, or manual/deleted miles earn nothing.
 *   3. The medal is dated by the day's newest workout and survives a later
 *      deletion (category `competition`, never revoked).
 *   4. The event view: window, state, the caller's miles, friends' counts.
 *   5. The route is self-only.
 *   6. Extra workouts reach friends by default only when long or fast.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/special-event-check.mjs
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import specialEventRoutes from "../dist/routes/specialEventRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import {
  evaluateForUser,
  revokeUnearnedBadges,
  seedExtraBadges,
} from "../dist/services/badgeService.js";
import {
  SPECIAL_EVENTS,
  eventsShowingOn,
  eventTargetMiles,
  getSpecialEventsForUser,
} from "../dist/services/specialEventService.js";
import { isNotableWorkout } from "../dist/services/notificationService.js";

const db = PostgresService.getInstance();
const EVENT = SPECIAL_EVENTS.find((e) => e.id === "champ_5k_2026");
const DAY = EVENT.date;
const BADGE = EVENT.badgeId;

const RUNNER = "se-runner";
const SHORT = "se-short";
const MANUAL = "se-manual";
const OFFDAY = "se-offday";
const FRIEND = "se-friend";
const ALL = [RUNNER, SHORT, MANUAL, OFFDAY, FRIEND];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`,
  );
}

let seq = 0;
async function walk(userId, day, miles, extra = {}) {
  const id = `se-w-${++seq}`;
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset, workout_type,
                           device_end_date, calories, total_duration, source, deleted_at)
     VALUES ($1, $2, $3, $4::date, $4::date, 0, 'walking', $4::date + ($5 || ' hours')::interval, 100, 1500, $6, $7)`,
    [
      id,
      userId,
      miles,
      day,
      String(extra.hour ?? 12),
      extra.source ?? "healthkit",
      extra.deletedAt ?? null,
    ],
  );
  return id;
}

const hasBadge = async (u) =>
  (
    await db.query(
      `SELECT 1 FROM user_badges WHERE user_id = $1 AND badge_id = $2`,
      [u, BADGE],
    )
  ).length > 0;

async function cleanup() {
  await db.query(`DELETE FROM user_badges WHERE user_id = ANY($1)`, [ALL]);
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1) OR friend_id = ANY($1)`,
    [ALL],
  );
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

const app = express();
app.use(express.json());
app.use(authenticateToken);
app.use("/users", specialEventRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

try {
  await cleanup();
  await seedExtraBadges();
  check(
    "medal is seeded",
    (
      await db.query(`SELECT category FROM badges WHERE badge_id = $1`, [BADGE])
    )[0]?.category,
    "competition",
  );
  for (const u of ALL) {
    await db.query(
      `INSERT INTO users (user_id, email, apple_sub, username) VALUES ($1, $2, $3, $4)`,
      [u, `${u}@example.test`, `${u}-sub`, u.replaceAll("-", "_")],
    );
  }
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted')`,
    [FRIEND, RUNNER],
  );

  // 1. Two walks on the day add up to the target (3.1 × 0.95 = 2.945).
  check(
    "target is the distance with the leeway",
    Math.round(eventTargetMiles(EVENT) * 1000) / 1000,
    2.945,
  );
  const a = await walk(RUNNER, DAY, 1.6, { hour: 9 });
  await evaluateForUser(RUNNER, [a]);
  check("1.6 mi: no medal yet", await hasBadge(RUNNER), false);
  const b = await walk(RUNNER, DAY, 1.4, { hour: 18 });
  await evaluateForUser(RUNNER, [b]);
  check("1.6 + 1.4 mi on the day: medal", await hasBadge(RUNNER), true);
  const dated = await db.query(
    `SELECT to_char(earned_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24') AS at FROM user_badges WHERE user_id = $1 AND badge_id = $2`,
    [RUNNER, BADGE],
  );
  check("dated by the day's newest walk", dated[0]?.at, `${DAY} 18`);

  // 2. Short, manual, deleted, another day.
  const s = await walk(SHORT, DAY, 2.5);
  await evaluateForUser(SHORT, [s]);
  check("2.5 mi: no medal", await hasBadge(SHORT), false);
  const m1 = await walk(MANUAL, DAY, 3.1, { source: "manual" });
  const m2 = await walk(MANUAL, DAY, 3.1, {
    deletedAt: new Date().toISOString(),
  });
  await evaluateForUser(MANUAL, [m1, m2]);
  check("manual + deleted miles: no medal", await hasBadge(MANUAL), false);
  const o = await walk(OFFDAY, "2026-11-13", 3.5);
  await evaluateForUser(OFFDAY, [o]);
  check("a 5K the day before: no medal", await hasBadge(OFFDAY), false);
  await evaluateForUser(OFFDAY, [], { allHolidays: true });
  check("...nor on a whole-history recalibrate", await hasBadge(OFFDAY), false);

  // 3. Never revoked.
  await db.query(
    `UPDATE workouts SET deleted_at = NOW() WHERE workout_id = $1`,
    [b],
  );
  await revokeUnearnedBadges(RUNNER);
  check("survives deleting a walk", await hasBadge(RUNNER), true);
  await db.query(
    `UPDATE workouts SET deleted_at = NULL WHERE workout_id = $1`,
    [b],
  );

  // 4. The view.
  check("not showing 15 days out", eventsShowingOn("2026-10-30").length, 0);
  check("showing 14 days out", eventsShowingOn("2026-10-31").length, 1);
  check("showing 3 days after", eventsShowingOn("2026-11-17").length, 1);
  check("gone 4 days after", eventsShowingOn("2026-11-18").length, 0);
  const before = (
    await getSpecialEventsForUser(FRIEND, { today: "2026-11-11" })
  ).events[0];
  check(
    "upcoming: state + days",
    [before?.state, before?.days_until],
    ["upcoming", 3],
  );
  check("upcoming: rewards", before?.reward_item_ids, [
    "champ_shorts",
    "boxing_gloves",
  ]);
  check(
    "friend sees the runner going and done",
    [before?.friends_going, before?.friends_done],
    [1, 1],
  );
  check(
    "friend preview names the runner",
    before?.friends_preview.map((p) => p.user_id),
    [RUNNER],
  );
  const day = (await getSpecialEventsForUser(RUNNER, { today: DAY })).events[0];
  check(
    "today: state, my miles, earned",
    [day?.state, day?.my_miles, day?.earned],
    ["today", 3, true],
  );
  const after = (await getSpecialEventsForUser(SHORT, { today: "2026-11-16" }))
    .events[0];
  check(
    "over: not earned",
    [after?.state, after?.earned, after?.my_miles],
    ["over", false, 2.5],
  );
  check(
    "strangers aren't counted",
    [after?.friends_going, after?.friends_preview.length],
    [0, 0],
  );

  // 5. Self only.
  const headers = {
    authorization: `Bearer ${await generateAccessToken(RUNNER)}`,
  };
  const own = await fetch(`${base}/users/${RUNNER}/special-events`, {
    headers,
  });
  check("own events: 200", own.status, 200);
  check("own events: an array", Array.isArray((await own.json()).events), true);
  check(
    "another person's events are refused",
    (await fetch(`${base}/users/${FRIEND}/special-events`, { headers })).status,
    403,
  );

  // 6. Notable extra workouts.
  check("0.6 mi stroll: not notable", isNotableWorkout(0.6, 720), false);
  check("1.5 mi easy walk: not notable", isNotableWorkout(1.5, 1800), false);
  check("3.1 mi walk: notable (far)", isNotableWorkout(3.1, 3600), true);
  check("2 mi at 7:30/mi: notable (fast)", isNotableWorkout(2, 900), true);
  check(
    "0.5 mi sprint: too short to count as fast",
    isNotableWorkout(0.5, 150),
    false,
  );
} finally {
  await cleanup().catch(() => {});
  server.close();
}

if (failures > 0) {
  console.error(`special-event-check: ${failures} failure(s)`);
  process.exit(1);
}
console.log("special-event-check: OK");
process.exit(0);
