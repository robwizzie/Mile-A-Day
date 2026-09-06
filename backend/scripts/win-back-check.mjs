/**
 * Win-back reminder check.
 *
 * On days 7, 14 and 30 of a quiet stretch the daily reminder swaps its copy
 * for a line about the gap and what the user's friends did meanwhile
 * (dailyReminderService.lapseContextFor + winBackCopy). Everything that can
 * go wrong here goes wrong silently: the wrong anchor makes day 7 land on
 * day 8 (nobody ever hears it), a friends query that reads the OTHER row
 * direction credits strangers, and a copy branch that drops the friends
 * line just reads generic. So the day arithmetic, the friend scoring and
 * the copy are all pinned against a seeded world.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/win-back-check.mjs
 */
import assert from "node:assert/strict";
import { PostgresService } from "../dist/services/DbService.js";
import {
  lapseContextFor,
  winBackCopy,
  WIN_BACK_DAYS,
} from "../dist/services/dailyReminderService.js";

const db = PostgresService.getInstance();

const ALICE = "wb-alice"; // last mile 7 days ago; friends bob + carol
const BOB = "wb-bob"; // walked 4.2 this week (top friend)
const CAROL = "wb-carol"; // walked 1.0 this week
const DAVE = "wb-dave"; // last mile 14 days ago, no friends
const ERIN = "wb-erin"; // joined 30 days ago, never walked
const FRANK = "wb-frank"; // last mile 8 days ago — not a win-back day
const GRACE = "wb-grace"; // last mile 7 days ago, but only a DUPLICATE since
const ALL = [ALICE, BOB, CAROL, DAVE, ERIN, FRANK, GRACE];

/** Today as a local_date string; the seed is anchored on it. */
const TODAY = new Date().toISOString().slice(0, 10);
function daysAgo(n) {
  const d = new Date(`${TODAY}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)}${ok ? "" : ` (expected ${JSON.stringify(expected)})`}`,
  );
}

async function cleanup() {
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1) OR friend_id = ANY($1)`,
    [ALL],
  );
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

let w = 0;
async function workout(userId, localDate, distance, extra = {}) {
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration, created_at,
                           deleted_at, exclusion_reason, source)
     VALUES ($1, $2, $3, $4::date, $4::date, 0, 'walking', $4::date + INTERVAL '18 hours',
             100, 900, NOW(), $5, $6, 'ci')`,
    [
      `wb-w-${++w}`,
      userId,
      distance,
      localDate,
      extra.deleted ? new Date() : null,
      extra.exclusion ?? null,
    ],
  );
}

async function seed() {
  for (const [id, joinedDaysAgo] of [
    [ALICE, 60],
    [BOB, 60],
    [CAROL, 60],
    [DAVE, 60],
    [ERIN, 30],
    [FRANK, 60],
    [GRACE, 60],
  ]) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, first_name, created_at, goal_miles)
       VALUES ($1, $2, $3, $4, $5, $6::date, 1.0)`,
      [
        id,
        id,
        id,
        `${id}@example.com`,
        id === BOB ? "Bobby" : null,
        daysAgo(joinedDaysAgo),
      ],
    );
  }
  // Friendships are stored per direction; only Alice's OWN rows may count.
  for (const [a, b] of [
    [ALICE, BOB],
    [ALICE, CAROL],
    [BOB, ALICE],
    [CAROL, ALICE],
    // Dave is Bob's friend but Bob is NOT Dave's — the reverse row alone must
    // not give Dave a friends line.
    [BOB, DAVE],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')`,
      [a, b],
    );
  }
  await workout(ALICE, daysAgo(7), 1.1);
  await workout(ALICE, daysAgo(9), 1.0);
  await workout(BOB, daysAgo(1), 2.2);
  await workout(BOB, daysAgo(3), 2.0);
  await workout(BOB, daysAgo(8), 5.0); // outside the 7-day window
  await workout(CAROL, daysAgo(2), 0.5);
  await workout(CAROL, daysAgo(6), 0.5);
  await workout(DAVE, daysAgo(14), 1.0);
  await workout(FRANK, daysAgo(8), 1.0);
  await workout(GRACE, daysAgo(7), 1.0);
  // A cross-app duplicate two days ago never counted as a mile, so it must
  // not count as a return either.
  await workout(GRACE, daysAgo(2), 1.0, { exclusion: "duplicate_source" });
  // A deleted walk yesterday, same rule.
  await workout(GRACE, daysAgo(1), 1.0, { deleted: true });
}

try {
  await cleanup();
  await seed();

  const candidates = ALL.map((user_id) => ({
    user_id,
    goal_miles: 1,
    tz_offset: 0,
    local_date: TODAY,
  }));
  const lapses = await lapseContextFor(candidates);

  check("win-back days are 7/14/30", [...WIN_BACK_DAYS].join(","), "7,14,30");
  check("Alice (day 7) is a win-back", lapses.has(ALICE), true);
  check("Frank (day 8) is not", lapses.has(FRANK), false);
  check("Bob (walked yesterday) is not", lapses.has(BOB), false);
  check("Dave (day 14) is a win-back", lapses.has(DAVE), true);
  check("Erin (joined 30 days ago, never walked) is a win-back", lapses.has(ERIN), true);
  check("Grace: a duplicate and a deleted walk don't count as a return", lapses.has(GRACE), true);

  const alice = lapses.get(ALICE);
  check("Alice days_quiet", alice?.days_quiet, 7);
  check("Alice has_walked", alice?.has_walked, true);
  check("Alice friends' miles this week (Bob 4.2 + Carol 1.0)", alice?.friend_miles_7d, 5.2);
  check("Alice active friends", alice?.active_friends, 2);
  check("Alice top friend is Bob by first name", alice?.top_friend, "Bobby");

  const dave = lapses.get(DAVE);
  check("Dave days_quiet", dave?.days_quiet, 14);
  check("Dave has no friends line (reverse row doesn't count)", dave?.active_friends, 0);

  const erin = lapses.get(ERIN);
  check("Erin days_quiet from signup", erin?.days_quiet, 30);
  check("Erin has_walked", erin?.has_walked, false);

  const grace = lapses.get(GRACE);
  check("Grace days_quiet", grace?.days_quiet, 7);

  // Copy: the friends line names the top friend and the others, and each
  // tier reads differently.
  const aliceCopy = winBackCopy(alice);
  check("Alice title", aliceCopy.title, "A week without a mile");
  check(
    "Alice body names Bob and the other friend with the week's miles",
    aliceCopy.body,
    "Bobby and 1 friend walked 5.2 mi this week. One mile brings your flame back.",
  );
  const daveCopy = winBackCopy(dave);
  check("Dave title", daveCopy.title, "Two weeks without a mile");
  check("Dave body has no friends line", daveCopy.body.includes("walked"), false);
  const erinCopy = winBackCopy(erin);
  check("Erin title", erinCopy.title, "A month in, no first mile yet");
  check(
    "one friend, big miles: no 'and 0 friends', whole miles past 10",
    winBackCopy({
      user_id: "x",
      days_quiet: 30,
      has_walked: true,
      friend_miles_7d: 23.4,
      active_friends: 1,
      top_friend: "Maddy",
    }).body,
    "Maddy walked 23 mi this week. Fresh start: one mile today, no pressure.",
  );
  // Every copy carries a title and body — a blank push is a blank banner.
  for (const days of WIN_BACK_DAYS) {
    for (const has_walked of [true, false]) {
      const c = winBackCopy({
        user_id: "x",
        days_quiet: days,
        has_walked,
        friend_miles_7d: 0,
        active_friends: 0,
        top_friend: null,
      });
      assert.ok(c.title.length > 0 && c.body.length > 0, `copy for day ${days}`);
    }
  }
} finally {
  await cleanup();
  await db.close?.();
}

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nwin-back check passed");
process.exit(0);
