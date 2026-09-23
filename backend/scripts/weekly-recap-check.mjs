/**
 * Weekly Recap check.
 *
 * The recap (`GET /users/:id/weekly-recap`) and its Saturday-evening push
 * (weeklyRecapService). Everything here fails SILENTLY when it is wrong: a
 * duplicate Strava copy counted into the week reads as a plausible bigger
 * number, an hour predicate off by one sends at 8 PM or never, a missing
 * claim sends twice, a missing device gate hands a shipped build a banner
 * that opens nothing. So the numbers are pinned against a seeded week and the
 * hour arithmetic against seeded timezone offsets at ONE fixed instant.
 *
 * The instant is the most recent past Saturday at 23:30 UTC — 19:30 in New
 * York (UTC-4), 16:30 in Los Angeles (UTC-7), and Sunday 08:30 in Tokyo
 * (UTC+9). Every assertion is a membership test or on seeded users' own rows,
 * never a global count (CI shares one database across scripts).
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/weekly-recap-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  getWeeklyRecap,
  sendWeeklyRecaps,
  weeklyRecapCandidates,
  weeklyRecapCopy,
  WeeklyRecapRequestError,
} from "../dist/services/weeklyRecapService.js";
import { seedWeeklyChallenges } from "../dist/services/weeklyChallengeService.js";
import { CLIENT_FEATURES } from "../dist/services/clientFeatures.js";
import { isCapExempt, selectPushTokens } from "../dist/services/pushNotificationService.js";
import { planWeeklyRecapSends } from "../dist/services/weeklyRecapService.js";
import { TRACKED_FEATURES } from "../dist/services/telemetryService.js";

const db = PostgresService.getInstance();

const HOUR = 3600_000;
const DAY = 86_400_000;
const ymd = (d) => d.toISOString().slice(0, 10);
const addDays = (s, n) => ymd(new Date(Date.parse(`${s}T12:00:00Z`) + n * DAY));

// The most recent Saturday strictly before today (UTC), at 23:30 UTC.
const now = new Date();
const back = (now.getUTCDay() - 6 + 7) % 7 || 7;
const SAT = ymd(new Date(now.getTime() - back * DAY));
const AT = new Date(`${SAT}T23:30:00Z`);
const S = addDays(SAT, -6); // the Sunday that starts the recapped week

const NY = -240;
const LA = -420;
const TOKYO = 540;

const A = "wr-a"; // NY, the subject: every figure is pinned on this user
const A19 = "wr-a19"; // NY, daily reminder at 19 → recap moves to 20:00
const B = "wr-b"; // LA, 7 for 7
const C = "wr-c"; // Tokyo
const D = "wr-d"; // A's friend, walked nothing, no device
const E = "wr-e"; // A's friend, blocked — must not appear on A's board
const OLD = "wr-old"; // NY, a shipped build: device WITHOUT weekly_recap_v1
const MIX = "wr-mix"; // NY, one new phone + one old iPad
const OFF = "wr-off"; // NY, weekly recap switched off
const IDLE = "wr-idle"; // NY, device + switch on, no workouts this week
const ALL = [A, A19, B, C, D, E, OLD, MIX, OFF, IDLE];

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)}${ok ? "" : ` (expected ${JSON.stringify(expected)})`}`,
  );
}

async function cleanup() {
  const q = (sql) => db.query(sql, [ALL]).catch((e) => console.warn(`cleanup: ${e.message}`));
  await q(`DELETE FROM in_app_notifications WHERE user_id = ANY($1)`);
  await q(`DELETE FROM notification_log WHERE user_id = ANY($1)`);
  await q(`DELETE FROM pending_notifications WHERE user_id = ANY($1)`);
  await q(`DELETE FROM weekly_recap_log WHERE user_id = ANY($1)`);
  await q(`DELETE FROM user_weekly_challenge_completions WHERE user_id = ANY($1)`);
  await q(`DELETE FROM user_weekly_challenges WHERE user_id = ANY($1)`);
  await q(`DELETE FROM workout_splits WHERE workout_id IN (SELECT workout_id FROM workouts WHERE user_id = ANY($1))`);
  await q(`DELETE FROM streak_coverage WHERE user_id = ANY($1)`);
  await q(`DELETE FROM user_blocks WHERE blocker_id = ANY($1) OR blocked_id = ANY($1)`);
  await q(`DELETE FROM friendships WHERE user_id = ANY($1) OR friend_id = ANY($1)`);
  await q(`DELETE FROM device_tokens WHERE user_id = ANY($1)`);
  await q(`DELETE FROM workouts WHERE user_id = ANY($1)`);
  await q(`DELETE FROM notification_settings WHERE user_id = ANY($1)`);
  await q(`DELETE FROM users WHERE user_id = ANY($1)`);
}

let w = 0;
async function walk(userId, day, distance, offset, { excluded = false, bundle = "com.apple.health" } = {}) {
  const id = `wr-w-${++w}`;
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration, created_at, source,
                           source_bundle_id, exclusion_reason)
     VALUES ($1, $2, $3, $4::date, $4::date, $5, 'walking', $4::date + INTERVAL '18 hours', 100, 900, NOW(), 'ci',
             $6, $7)`,
    [id, userId, distance, day, offset, bundle, excluded ? "duplicate_source" : null],
  );
  return id;
}

async function split(workoutId, n, pace, distance = 1.0) {
  await db.query(
    `INSERT INTO workout_splits (workout_id, split_number, split_duration, split_distance, split_pace)
     VALUES ($1, $2, $3, $4, $3)`,
    [workoutId, n, pace, distance],
  );
}

async function user(id, { tz, recap = true, reminderHour = 18, features = null, first = null }) {
  await db.query(
    `INSERT INTO users (user_id, username, first_name, apple_sub, email, created_at, goal_miles)
     VALUES ($1, $2, $3, $4, $5, NOW() - INTERVAL '120 days', 1.0)`,
    [id, id, first ?? id, id, `${id}@example.com`],
  );
  await db.query(
    `INSERT INTO notification_settings (user_id, timezone_offset_minutes, weekly_recap_enabled, daily_reminder_hour)
     VALUES ($1, $2, $3, $4)`,
    [id, tz, recap, reminderHour],
  );
  if (features) {
    await db.query(
      `INSERT INTO device_tokens (user_id, device_token, environment, client_features)
       VALUES ($1, $2, 'sandbox', $3::text[])`,
      [id, `wr-token-${id}`, features],
    );
  }
}

const befriend = (a, b) =>
  db.query(`INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')`, [a, b]);

async function seed() {
  const RECAP = [CLIENT_FEATURES.weeklyRecapV1];
  await user(A, { tz: NY, features: RECAP, first: "Ann" });
  await user(A19, { tz: NY, features: RECAP, reminderHour: 19 });
  await user(B, { tz: LA, features: RECAP });
  await user(C, { tz: TOKYO, features: RECAP });
  await user(D, { tz: NY });
  await user(E, { tz: NY, features: RECAP });
  await user(OLD, { tz: NY, features: [CLIENT_FEATURES.weeklyChallengeV1] });
  await user(OFF, { tz: NY, features: RECAP, recap: false });
  await user(IDLE, { tz: NY, features: RECAP });

  // A's week: 1.2, 0.96 (tolerance), 0.5 + an excluded Strava twin, a covered
  // rest day, 2.3 with splits, 1.0, 1.1.
  await walk(A, S, 1.2, NY);
  await walk(A, addDays(S, 1), 0.96, NY);
  await walk(A, addDays(S, 2), 0.5, NY);
  const twin = await walk(A, addDays(S, 2), 1.0, NY, { excluded: true, bundle: "com.strava.stravaride" });
  await split(twin, 1, 400); // plausible, but its workout doesn't count
  await db.query(
    `INSERT INTO streak_coverage (user_id, local_date, kind) VALUES ($1, $2::date, 'streak_save')`,
    [A, addDays(S, 3)],
  );
  const long = await walk(A, addDays(S, 4), 2.3, NY);
  await split(long, 1, 600);
  await split(long, 2, 580);
  await split(long, 3, 200, 0.3); // a vehicle-fast partial: not a real mile
  await walk(A, addDays(S, 5), 1.0, NY);
  await walk(A, SAT, 1.1, NY);
  // The three days before the week: a 3-day streak coming in, and 3.0 mi of
  // prior week.
  for (const n of [-3, -2, -1]) await walk(A, addDays(S, n), 1.0, NY);

  await walk(A19, S, 1.0, NY);
  for (let n = 0; n < 7; n++) await walk(B, addDays(S, n), 1.0, LA);
  await walk(C, addDays(S, 1), 4.0, TOKYO);
  await walk(C, addDays(S, 2), 5.0, TOKYO);
  await walk(E, addDays(S, 1), 12.0, NY);
  await walk(OLD, S, 1.0, NY);
  await user(MIX, { tz: NY, features: RECAP });
  await db.query(
    `INSERT INTO device_tokens (user_id, device_token, environment, client_features)
     VALUES ($1, $2, 'sandbox', '{}')`,
    [MIX, `wr-token-${MIX}-ipad`],
  );
  await walk(MIX, S, 1.0, NY);
  await walk(OFF, S, 1.0, NY);
  await walk(IDLE, addDays(S, -3), 1.0, NY); // last week, not this one

  await befriend(A, B);
  await befriend(C, A); // the other direction: the circle is either way round
  await befriend(A, D);
  await befriend(A, E);
  await db.query(`INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [A, E]);

  await seedWeeklyChallenges();
  const [ch] = await db.query(
    `SELECT challenge_key, title, unit FROM weekly_challenges WHERE metric = 'total_distance' ORDER BY challenge_key LIMIT 1`,
  );
  await db.query(
    `INSERT INTO user_weekly_challenges (user_id, week_start, challenge_key, target, baseline)
     VALUES ($1, $2::date, $3, 5, NULL)`,
    [A, S, ch.challenge_key],
  );
  return ch;
}

try {
  await cleanup();
  const challenge = await seed();

  // ── The recap's numbers ────────────────────────────────────────────────
  const r = await getWeeklyRecap(A, S, AT);
  // WEEKLY_RECAP_DUMP=1 prints the seeded response — the contract, as served.
  if (process.env.WEEKLY_RECAP_DUMP) console.log(JSON.stringify(r, null, 2));
  check("week_start is the Sunday", r.week_start, S);
  check("week_end is the Saturday", r.week_end, SAT);
  check("week ending today (local Sat 19:30) is not complete", r.is_complete, false);
  check("unit_note", r.unit_note, "miles");
  check("seven days, in order", r.days.map((d) => d.date), [0, 1, 2, 3, 4, 5, 6].map((n) => addDays(S, n)));
  check("day miles (the excluded twin never counts)", r.days.map((d) => d.miles), [1.2, 0.96, 0.5, 0, 2.3, 1, 1.1]);
  check("goal_met uses the 0.95 tolerance", r.days.map((d) => d.goal_met), [true, true, false, false, true, true, true]);
  check("covered marks the streak_coverage day only", r.days.map((d) => d.covered), [false, false, false, true, false, false, false]);
  check("days_goal_met", r.days_goal_met, 5);
  check("total_miles (counted only)", r.total_miles, 7.06);
  check("prior_week_miles", r.prior_week_miles, 3);
  check("workouts (counted only)", r.workouts, 6);
  check("total_duration_seconds", r.total_duration_seconds, 6 * 900);
  check("longest_workout_miles", r.longest_workout_miles, 2.3);
  check("fastest mile: real, full-mile, counted splits only", r.fastest_mile_pace_seconds, 580);
  check("goal_miles", r.goal_miles, 1);
  check("streak_at_week_start (three days in)", r.streak_at_week_start, 3);
  check("current_streak is a number", typeof r.current_streak, "number");
  check("weekly challenge: the served row", r.weekly_challenge && {
    name: r.weekly_challenge.name,
    completed: r.weekly_challenge.completed,
    value: r.weekly_challenge.value,
    target: r.weekly_challenge.target,
    unit: r.weekly_challenge.unit,
  }, { name: challenge.title, completed: false, value: 7.06, target: 5, unit: challenge.unit });
  check("friends: rank among the circle, blocked friend excluded", r.friends && { rank: r.friends.rank, of: r.friends.of }, { rank: 2, of: 4 });
  check("friends: top three in order", r.friends?.top.map((f) => f.user_id), [C, A, B]);
  check("friends: is_me marks the viewer", r.friends?.top.find((f) => f.is_me)?.user_id, A);
  check("friends: the Tokyo friend's miles", r.friends?.top[0].miles, 9);
  check("highlights: week-on-week, factual", r.highlights, ["Up 135% on last week"]);
  check("push copy", weeklyRecapCopy(r), {
    title: "Your week: 7.1 mi, 5 of 7 days",
    body: "Up 135% on last week. Tap to see your recap and share it.",
  });

  const b = await getWeeklyRecap(B, S, new Date(AT.getTime() + 3 * HOUR));
  check("B: 7 for 7 highlight", b.highlights.includes("7 for 7"), true);
  check("B: 7/7 title carries the flame", weeklyRecapCopy(b).title, "Your week: 7.0 mi, 7 of 7 days 🔥");
  check("B: no served challenge → null", b.weekly_challenge, null);
  check("B: prior_week_miles null for an account with no earlier walks", b.prior_week_miles, null);
  const idle = await getWeeklyRecap(IDLE, S, AT);
  check("IDLE: no friends → friends null", idle.friends, null);
  check("IDLE: zero workouts, no highlights", [idle.workouts, idle.highlights], [0, []]);

  // ── Which week ────────────────────────────────────────────────────────
  check("default at local Sat 19:30 → the week ending today", (await getWeeklyRecap(A, undefined, AT)).week_start, S);
  check("default at local Sat 14:30 → the last completed week", (await getWeeklyRecap(A, undefined, new Date(AT.getTime() - 5 * HOUR))).week_start, addDays(S, -7));
  check("default on Sunday morning → the week just finished", (await getWeeklyRecap(A, undefined, new Date(AT.getTime() + 12 * HOUR))).week_start, S);
  check("a mid-week date resolves to its Sunday", (await getWeeklyRecap(A, addDays(S, 3), AT)).week_start, S);
  check("the same week a day later is complete", (await getWeeklyRecap(A, S, new Date(AT.getTime() + DAY))).is_complete, true);
  let futureCode = null;
  try {
    await getWeeklyRecap(A, addDays(S, 7), AT);
  } catch (e) {
    futureCode = e instanceof WeeklyRecapRequestError ? e.code : e.message;
  }
  check("a week that hasn't started → 400 week_in_future", futureCode, "week_in_future");
  let badCode = null;
  try {
    await getWeeklyRecap(A, "2026-02-30", AT);
  } catch (e) {
    badCode = e instanceof WeeklyRecapRequestError ? e.code : e.message;
  }
  check("an impossible date → 400 invalid_week_start", badCode, "invalid_week_start");

  // ── Who is due, and when ─────────────────────────────────────────────
  const dueAt = async (at) => (await weeklyRecapCandidates(at)).map((c) => c.user_id).filter((id) => ALL.includes(id)).sort();
  // E is NY, capable and active too — blocked by A, which is A's business.
  // OLD (a shipped build) and MIX are due as well: nobody loses the recap.
  check("due at NY Sat 19:30", await dueAt(AT), [A, E, MIX, OLD].sort());
  const a = (await weeklyRecapCandidates(AT)).find((c) => c.user_id === A);
  check("candidate carries the week", a && [a.week_start, a.local_date], [S, SAT]);
  check("an hour later: the reminder-at-19 user's turn, not A's again", await dueAt(new Date(AT.getTime() + HOUR)), [A19]);
  check("three hours later: Los Angeles", await dueAt(new Date(AT.getTime() + 3 * HOUR)), [B]);
  check("thirteen hours earlier: Tokyo", await dueAt(new Date(AT.getTime() - 13 * HOUR)), [C]);
  check("never: recap switched off", (await weeklyRecapCandidates(AT)).some((c) => c.user_id === OFF), false);
  check("never: no counted workout this week", (await weeklyRecapCandidates(AT)).some((c) => c.user_id === IDLE), false);
  check("a day early (Fri 19:30 NY) nobody", await dueAt(new Date(AT.getTime() - DAY)), []);

  // ── One variant per device ───────────────────────────────────────────
  const FEATURE = CLIENT_FEATURES.weeklyRecapV1;
  const shape = (plan) =>
    plan.map((s) => ({
      variant: s.variant,
      supported: s.opts.deviceFeature.supported,
      skipInbox: s.opts.skipInbox,
      title: s.payload.title,
      data: s.payload.data ?? null,
    }));
  const planA = await planWeeklyRecapSends(A, r);
  check("capable-only user: the new push, with its week", shape(planA), [
    { variant: "v1", supported: true, skipInbox: false, title: "Your week: 7.1 mi, 5 of 7 days", data: { week_start: S } },
  ]);
  const old = await getWeeklyRecap(OLD, S, AT);
  const planOld = await planWeeklyRecapSends(OLD, old);
  check("legacy-only user: exactly the push shipped builds get today (no data)", planOld.map((s) => ({ ...s.payload, supported: s.opts.deviceFeature.supported, skipInbox: s.opts.skipInbox })), [
    {
      title: "Your week in review",
      body: "1.0 mi · 1 workout · best pace 15:00 — tap to see your recap and share it.",
      type: "weekly_recap",
      supported: false,
      skipInbox: false,
    },
  ]);
  const planMix = await planWeeklyRecapSends(MIX, await getWeeklyRecap(MIX, S, AT));
  check("mixed devices: new to the new device, legacy to the old, ONE inbox row", planMix.map((s) => [s.variant, s.opts.deviceFeature.supported, s.opts.skipInbox]), [
    ["v1", true, false],
    ["legacy", false, true],
  ]);
  const tokens = async (id, supported) =>
    (await selectPushTokens(id, { feature: FEATURE, supported })).map((t) => t.device_token).sort();
  const mixNew = await tokens(MIX, true);
  const mixOld = await tokens(MIX, false);
  const mixAll = (await selectPushTokens(MIX)).map((t) => t.device_token).sort();
  check("mixed: the new push rings only the capable device", mixNew, [`wr-token-${MIX}`]);
  check("mixed: the legacy push rings only the old device (no features)", mixOld, [`wr-token-${MIX}-ipad`]);
  check("never both to one device, and every device once", [mixNew.filter((t) => mixOld.includes(t)).length, [...mixNew, ...mixOld].sort()], [0, mixAll]);
  check("legacy class holds a device with OTHER features", await tokens(OLD, false), [`wr-token-${OLD}`]);
  check("…and the capable class none of it", await tokens(OLD, true), []);

  // ── The send ─────────────────────────────────────────────────────────
  const inbox = async (id) =>
    db.query(`SELECT title, body, data FROM in_app_notifications WHERE user_id = $1 AND type = 'weekly_recap'`, [id]);
  await sendWeeklyRecaps(AT);
  await new Promise((res) => setTimeout(res, 300)); // inbox writes are fire-and-forget
  const rowsA = await inbox(A);
  check("A got one recap", rowsA.length, 1);
  check("…personalised title", rowsA[0]?.title, "Your week: 7.1 mi, 5 of 7 days");
  check("…data is {week_start} as a string", rowsA[0]?.data, { week_start: S });
  check("…claimed in weekly_recap_log", (await db.query(`SELECT 1 FROM weekly_recap_log WHERE user_id = $1 AND week_start = $2::date`, [A, S])).length, 1);
  check("A is no longer a candidate once claimed", (await weeklyRecapCandidates(AT)).some((c) => c.user_id === A), false);
  await sendWeeklyRecaps(AT);
  await new Promise((res) => setTimeout(res, 300));
  check("a second pass sends nothing more", [(await inbox(A)).length, (await inbox(OLD)).length, (await inbox(MIX)).length], [1, 1, 1]);
  const rowsOld = await inbox(OLD);
  check("legacy-only user still gets the legacy recap", rowsOld.map((x) => [x.title, x.data]), [["Your week in review", {}]]);
  const rowsMix = await inbox(MIX);
  check("mixed user: one inbox row, the new variant", rowsMix.map((x) => [x.title, x.data]), [["Your week: 1.0 mi, 1 of 7 days", { week_start: S }]]);
  const claims = async (id) =>
    (await db.query(`SELECT 1 FROM weekly_recap_log WHERE user_id = $1 AND week_start = $2::date`, [id, S])).length;
  check("one claim per user-week (legacy, mixed)", [await claims(OLD), await claims(MIX)], [1, 1]);
  for (const id of [OFF, IDLE, A19, B, C]) {
    check(`${id} got nothing at NY 19:30`, (await inbox(id)).length, 0);
  }

  process.env.WEEKLY_RECAP_DISABLED = "true";
  await sendWeeklyRecaps(new Date(AT.getTime() + 3 * HOUR));
  await new Promise((res) => setTimeout(res, 300));
  check("kill switch: LA's turn sends nothing", (await inbox(B)).length, 0);
  delete process.env.WEEKLY_RECAP_DISABLED;
  await sendWeeklyRecaps(new Date(AT.getTime() + 3 * HOUR));
  await new Promise((res) => setTimeout(res, 300));
  check("switch off again: LA gets its recap", (await inbox(B)).length, 1);

  // ── Config ───────────────────────────────────────────────────────────
  check("weekly_recap is cap-exempt (once a week, about your own account)", isCapExempt("weekly_recap"), true);
  check("telemetry allowlists the recap events", ["weekly_recap_opened", "weekly_recap_shared"].every((f) => TRACKED_FEATURES.has(f)), true);
} finally {
  await cleanup();
  await db.close();
}

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nweekly-recap check passed");
process.exit(0);
