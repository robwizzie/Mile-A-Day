/**
 * Streak last-call check.
 *
 * Two hours before local midnight, a user with a live streak and no mile
 * gets one more push (lastCallService). What goes wrong here goes wrong
 * silently: an hour predicate off by one sends it at 11 PM or never, a
 * missed reminder-hour guard doubles up with the daily reminder, a stale
 * stored streak announces a streak that already broke. The hour arithmetic
 * is pinned by seeding users at different timezone offsets against ONE
 * fixed instant, and the send path against a real inbox.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/last-call-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  lastCallCandidates,
  lastCallCopy,
  sendPendingLastCalls,
  LAST_CALL_LOCAL_HOUR,
} from "../dist/services/lastCallService.js";

const db = PostgresService.getInstance();

// The instant is NOW (refreshCurrentStreak reads the real clock), and the
// seeded timezone offsets are chosen so that, at this instant, one cohort's
// local clock reads 22:xx and another's 21:xx. Offsets are plain minutes,
// so any value works for the arithmetic under test.
const AT = new Date();
const utcMinutes = AT.getUTCHours() * 60 + AT.getUTCMinutes();
const TEN_PM = 22 * 60 - utcMinutes; // local 22:xx at AT
const NINE_PM = TEN_PM - 60; // local 21:xx at AT
const localDate = (offsetMinutes, daysBack = 0) =>
  new Date(AT.getTime() + offsetMinutes * 60_000 - daysBack * 86_400_000)
    .toISOString()
    .slice(0, 10);
const TODAY_LOCAL = localDate(TEN_PM);

const DUE = "lc-due"; // streak 12, no mile, 10 PM → last call
const ONE = "lc-one"; // streak 1, no mile → the "make it 2 days" copy
const DONE = "lc-done"; // walked today → not
const NOSTREAK = "lc-nostreak"; // streak 0 → not
const OPTED_OUT = "lc-optout"; // daily reminders off → not
const SAME_HOUR = "lc-samehour"; // reminder hour IS 22 → the reminder covers it
const EARLY = "lc-early"; // local 21:00 → not yet
const NO_DEVICE = "lc-nodevice"; // nowhere to send
const NEARLY = "lc-nearly"; // 0.96 of the goal walked → counts as done
const STALE = "lc-stale"; // stored streak 9 but nothing walked for a week → refresh says 0
const ALL = [DUE, ONE, DONE, NOSTREAK, OPTED_OUT, SAME_HOUR, EARLY, NO_DEVICE, NEARLY, STALE];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)}${ok ? "" : ` (expected ${JSON.stringify(expected)})`}`,
  );
}

async function cleanup() {
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM notification_log WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM device_tokens WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM notification_settings WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

let w = 0;
async function walk(userId, day, distance, offset = TEN_PM) {
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration, created_at, source)
     VALUES ($1, $2, $3, $4::date, $4::date, $5, 'walking', $4::date + INTERVAL '18 hours', 100, 900, NOW(), 'ci')`,
    [`lc-w-${++w}`, userId, distance, day, offset],
  );
}

async function seed() {
  const users = [
    [DUE, 12, TEN_PM, true, 18, true],
    [ONE, 1, TEN_PM, true, 18, true],
    [DONE, 5, TEN_PM, true, 18, true],
    [NOSTREAK, 0, TEN_PM, true, 18, true],
    [OPTED_OUT, 7, TEN_PM, false, 18, true],
    [SAME_HOUR, 7, TEN_PM, true, LAST_CALL_LOCAL_HOUR, true],
    [EARLY, 7, NINE_PM, true, 18, true],
    [NO_DEVICE, 7, TEN_PM, true, 18, false],
    [NEARLY, 7, TEN_PM, true, 18, true],
    [STALE, 9, TEN_PM, true, 18, true],
  ];
  for (const [id, streak, tz, remindersOn, hour, device] of users) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, current_streak, created_at, goal_miles)
       VALUES ($1, $2, $3, $4, $5, NOW() - INTERVAL '60 days', 1.0)`,
      [id, id, id, `${id}@example.com`, streak],
    );
    await db.query(
      `INSERT INTO notification_settings (user_id, timezone_offset_minutes, daily_reminder_enabled, daily_reminder_hour)
       VALUES ($1, $2, $3, $4)`,
      [id, tz, remindersOn, hour],
    );
    if (device) {
      await db.query(
        `INSERT INTO device_tokens (user_id, device_token, environment) VALUES ($1, $2, 'sandbox')`,
        [id, `lc-token-${id}`],
      );
    }
  }
  // Yesterday's mile keeps the refreshed streak alive for everyone but STALE.
  for (const id of [ONE, DONE, OPTED_OUT, SAME_HOUR, NO_DEVICE, NEARLY]) {
    await walk(id, localDate(TEN_PM, 1), 1.0);
  }
  // DUE's stored 12 has to be TRUE — the send path refreshes it and uses the
  // refreshed number in the copy.
  for (let d = 1; d <= 12; d++) await walk(DUE, localDate(TEN_PM, d), 1.0);
  await walk(EARLY, localDate(NINE_PM, 1), 1.0, NINE_PM);
  await walk(DONE, TODAY_LOCAL, 1.2);
  await walk(NEARLY, TODAY_LOCAL, 0.96); // >= 0.95 × goal is a done day
  await walk(STALE, localDate(TEN_PM, 8), 1.0); // a week ago — the stored 9 is a lie
}

try {
  await cleanup();
  await seed();

  const ids = (await lastCallCandidates(AT)).map((c) => c.user_id).sort();
  check("candidates at local 10 PM with a streak and no mile", ids.join(","), [DUE, ONE, STALE].sort().join(","));
  check("…DONE walked today", ids.includes(DONE), false);
  check("…NEARLY's 0.96 counts as done (tolerance)", ids.includes(NEARLY), false);
  check("…NOSTREAK has nothing to lose", ids.includes(NOSTREAK), false);
  check("…OPTED_OUT turned reminders off", ids.includes(OPTED_OUT), false);
  check("…SAME_HOUR's reminder already fires at 22", ids.includes(SAME_HOUR), false);
  check("…EARLY is only at 21:00", ids.includes(EARLY), false);
  check("…NO_DEVICE has nowhere to receive it", ids.includes(NO_DEVICE), false);

  const due = (await lastCallCandidates(AT)).find((c) => c.user_id === DUE);
  check("candidate carries the local date", due?.local_date, TODAY_LOCAL);
  check("candidate carries today's miles", due?.today_miles, 0);

  // An hour later nobody at TEN_PM is due any more (23:00), and EARLY is.
  const later = (await lastCallCandidates(new Date(AT.getTime() + 3600_000))).map((c) => c.user_id);
  check("an hour later the 10 PM cohort is past its call", later.includes(DUE), false);
  check("…and the 9 PM cohort's turn has come", later.includes(EARLY), true);

  check("copy for a 12-day streak", lastCallCopy(12).title, "Last call: 12-day streak on the line");
  check("copy for a 1-day streak", lastCallCopy(1).body, "Two hours to midnight. One mile makes it a 2-day streak.");

  // The send path: DUE and ONE get an inbox row, STALE's refreshed streak
  // is 0 so it gets nothing, nobody else is touched.
  const sent = await sendPendingLastCalls(AT);
  await new Promise((r) => setTimeout(r, 300)); // inbox writes are fire-and-forget
  const inbox = async (id) =>
    (
      await db.query(
        `SELECT title, data FROM in_app_notifications WHERE user_id = $1 AND type = 'streak_last_call'`,
        [id],
      )
    );
  check("sent count", sent, 2);
  check("DUE has one last call in the inbox", (await inbox(DUE)).length, 1);
  check("…with the streak in the title", (await inbox(DUE))[0].title, "Last call: 12-day streak on the line");
  check("…and string-valued data", typeof (await inbox(DUE))[0].data.streak, "string");
  check("ONE has one", (await inbox(ONE)).length, 1);
  check("STALE (stored 9, refreshed 0) got nothing", (await inbox(STALE)).length, 0);
  check("…and its stored streak was corrected", (await db.query(`SELECT current_streak FROM users WHERE user_id = $1`, [STALE]))[0].current_streak, 0);
  check("DONE got nothing", (await inbox(DONE)).length, 0);
  check("EARLY got nothing yet", (await inbox(EARLY)).length, 0);
} finally {
  await cleanup();
  await db.close();
}

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nlast-call check passed");
process.exit(0);
