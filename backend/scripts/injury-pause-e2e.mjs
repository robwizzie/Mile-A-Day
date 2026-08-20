// End-to-end proof of the injury-pause (Recovery Mode) rules against a real
// Postgres. There is no unit-test runner in this repo, so this is the evidence
// that the streak walk actually elides a pause instead of covering it.
//
// Run:
//   createdb mad_injury_test && psql -d mad_injury_test \
//     -c 'CREATE EXTENSION pg_trgm; CREATE EXTENSION pgcrypto;'
//   npm run build
//   DATABASE_URL=postgres://<user>:<pw>@localhost:5432/mad_injury_test \
//     APP_JWT_SECRET=testsecret PORT=3987 node dist/server.js   # applies migrations
//   node scripts/injury-pause-e2e.mjs
//
// Seeds day-by-day workout history and asserts the streak walk's real output.
// Expects a FRESH database — it seeds fixed user ids and does not clean up.
const DB_URL =
  process.env.DATABASE_URL ?? "postgres://wo:wo@localhost:5432/mad_injury_test";
process.env.DATABASE_URL = DB_URL;
process.env.APP_JWT_SECRET = process.env.APP_JWT_SECRET ?? "testsecret";

const B = new URL("../dist", import.meta.url).pathname;
const { PostgresService } = await import(`${B}/services/DbService.js`);
const { getActiveStreak } = await import(`${B}/services/workoutService.js`);
const { refreshCurrentStreak } = await import(
  `${B}/services/leaderboardService.js`
);
const ips = await import(`${B}/services/injuryPauseService.js`);
const core = await import(`${B}/services/streakFeatureCore.js`);

const db = PostgresService.getInstance();
let pass = 0,
  fail = 0;
const results = [];
function check(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  ok ? pass++ : fail++;
  results.push(
    `${ok ? "PASS" : "FAIL"}  ${name}${ok ? "" : `\n        got ${JSON.stringify(got)} want ${JSON.stringify(want)}`}`,
  );
}
async function throws(name, fn, wantMsg) {
  try {
    await fn();
    check(name, "no-throw", `throws:${wantMsg}`);
  } catch (e) {
    check(name, e.message, wantMsg);
  }
}

const today = new Date().toISOString().slice(0, 10);
const d = (n) => core.dateStrMinus(today, n); // n days ago

async function mkUser(id, { enrolled = true } = {}) {
  await db.query(
    `INSERT INTO users (user_id, apple_sub, username, goal_miles, streak_features_at)
     VALUES ($1,$2,$3,1.0,$4) ON CONFLICT (user_id) DO NOTHING`,
    [id, id, id, enrolled ? new Date().toISOString() : null],
  );
}
// Seed one qualifying (1.2 mi) day per date in [fromAgo..toAgo] inclusive, counting back.
async function seedDays(id, fromAgo, toAgo) {
  for (let n = toAgo; n <= fromAgo; n++) {
    const date = d(n);
    await db.query(
      `INSERT INTO workouts (workout_id,user_id,distance,local_date,date,timezone_offset,
         workout_type,device_end_date,calories,total_duration,source,speed_flagged,feed_role)
       VALUES ($1,$2,1.2,$3::date,$3::timestamptz,0,'running',$3::timestamptz,100,600,'test',false,'daily_mile')
       ON CONFLICT (workout_id) DO NOTHING`,
      [`${id}-${date}`, id, date],
    );
  }
}
const streakOf = async (id) => (await getActiveStreak(id)).streak;

// ---------------------------------------------------------------- RULE 1: unlock at 90
await mkUser("u-short");
await seedDays("u-short", 89, 1); // 89-day streak ending yesterday
await mkUser("u-long");
await seedDays("u-long", 400, 1); // 400-day streak ending yesterday
check("R1 89-day streak reads as 89", await streakOf("u-short"), 89);
check("R1 400-day streak reads as 400", await streakOf("u-long"), 400);
await refreshCurrentStreak("u-short");
await refreshCurrentStreak("u-long");
await throws(
  "R1 89-day streak REJECTED",
  () => ips.startInjuryPause("u-short"),
  "streak_too_short",
);
check(
  "R1 400-day eligible",
  (await ips.getInjuryPauseStatus("u-long")).eligible,
  true,
);

// ---------------------------------------------------------------- RULE 2: backdate <= 7
await mkUser("u-back");
await seedDays("u-back", 400, 8);
await refreshCurrentStreak("u-back");
await throws(
  "R2 backdate 8 days REJECTED",
  () => ips.startInjuryPause("u-back", d(8)),
  "backdate_too_far",
);
await throws(
  "R2 future date REJECTED",
  () => ips.startInjuryPause("u-back", core.dateStrPlus(today, 1)),
  "started_on_in_future",
);
await throws(
  "R2 malformed date REJECTED",
  () => ips.startInjuryPause("u-back", "07-04-2026"),
  "invalid_started_on",
);
const backSt = await ips.startInjuryPause("u-back", d(7));
check("R2 backdate 7 days ACCEPTED", backSt.active.started_on, d(7));
check(
  "R2 froze pre-injury streak (393 = 400 - 7 missed)",
  backSt.active.frozen_streak,
  393,
);

// ---------------------------------------------------------------- RULE 3: no growth while paused
await mkUser("u-freeze");
await seedDays("u-freeze", 400, 1);
await refreshCurrentStreak("u-freeze");
const frozenAt = (await ips.startInjuryPause("u-freeze")).active.frozen_streak;
check("R3 frozen at 400", frozenAt, 400);
check(
  "R3 streak reads frozen value while paused",
  await streakOf("u-freeze"),
  400,
);
await seedDays("u-freeze", 0, 0); // they walk a mile TODAY, mid-pause
check(
  "R3 running during pause does NOT grow the streak",
  await streakOf("u-freeze"),
  400,
);
check("R3 isPaused true", await ips.isPaused("u-freeze"), true);

// ---------------------------------------------------------------- RULE 4: minimum 30 days
await throws(
  "R4 cannot end on day 1",
  () => ips.endInjuryPause("u-freeze"),
  "minimum_not_reached",
);
check(
  "R4 can_end false on day 1",
  (await ips.getInjuryPauseStatus("u-freeze")).active.can_end,
  false,
);
// age the pause to exactly 30 days
await db.query(
  `UPDATE streak_pauses SET started_on = $1::date WHERE user_id='u-freeze'`,
  [d(29)],
);
check(
  "R4 can_end true on day 30",
  (await ips.getInjuryPauseStatus("u-freeze")).active.can_end,
  true,
);

// ---------------------------------------------------------------- RULE 7: bridging on resume
// Faithful shape: a 370-day run ending d(31), then a real 31-day gap that a
// pause opened at d(30) covers. Nothing is deleted — the history is exactly
// what an injured user's would look like.
await mkUser("u-bridge");
await seedDays("u-bridge", 400, 31); // 370 qualifying days
await db.query(
  `INSERT INTO streak_pauses (user_id, started_on, frozen_streak) VALUES ('u-bridge',$1::date,370)`,
  [d(30)],
);
check(
  "R7 streak holds at frozen value mid-pause",
  await streakOf("u-bridge"),
  370,
);
check(
  "R7 can end after 31 days paused",
  (await ips.getInjuryPauseStatus("u-bridge")).active.can_end,
  true,
);
await ips.endInjuryPause("u-bridge");
check("R7 streak survives the pause intact", await streakOf("u-bridge"), 370);
await seedDays("u-bridge", 0, 0); // first run back, today
check(
  "R7 first day back continues from frozen value",
  await streakOf("u-bridge"),
  371,
);

// ---------------------------------------------------------------- RULE 6: re-earn 90 days
const st6 = await ips.getInjuryPauseStatus("u-bridge");
check(
  "R6 blocked immediately after resuming",
  [st6.eligible, st6.reason],
  [false, "rebuilding"],
);
check("R6 re-earn progress counts days since resume", st6.reearn_progress, 1);
await throws(
  "R6 second pause REJECTED while rebuilding",
  () => ips.startInjuryPause("u-bridge"),
  "rebuilding",
);
// Now simulate the same user 90+ days into rebuilding: pause sits further back
// and an unbroken run of qualifying days follows the resume.
await db.query(
  `UPDATE streak_pauses SET started_on = $1::date, resumed_on = $2::date WHERE user_id='u-bridge'`,
  [d(150), d(120)],
);
await seedDays("u-bridge", 120, 0);
await refreshCurrentStreak("u-bridge");
const st6b = await ips.getInjuryPauseStatus("u-bridge");
check(
  "R6 eligible again after 90 rebuilt days",
  [st6b.eligible, st6b.reearn_progress],
  [true, 90],
);

// ---------------------------------------------------------------- RULE 5: 180-day cap
await mkUser("u-cap");
await seedDays("u-cap", 400, 200);
await refreshCurrentStreak("u-cap");
await db.query(
  `INSERT INTO streak_pauses (user_id, started_on, frozen_streak) VALUES ('u-cap',$1::date,201)`,
  [d(199)],
);
await refreshCurrentStreak("u-cap");
const beforeCap = await db.query(
  `SELECT current_streak, longest_streak FROM users WHERE user_id='u-cap'`,
);
check(
  "R5 streak frozen while over-long pause is open",
  beforeCap[0].current_streak,
  201,
);
const expired = await ips.expirePausesPastCap();
check("R5 cap expired exactly one pause", expired, 1);
const afterCap = await db.query(
  `SELECT current_streak, longest_streak FROM users WHERE user_id='u-cap'`,
);
check("R5 streak ENDS at the cap", afterCap[0].current_streak, 0);
check(
  "R5 longest_streak keeps the frozen value",
  afterCap[0].longest_streak,
  201,
);

// ---------------------------------------------------------------- RULE 8: sweep can't break a paused user
const { runStreakFeaturesSweep } = await import(
  `${B}/services/streakFeatureService.js`
);
await mkUser("u-sweep");
await seedDays("u-sweep", 400, 5);
await refreshCurrentStreak("u-sweep");
await ips.startInjuryPause("u-sweep", d(4));
await db.query(`DELETE FROM streak_events WHERE user_id='u-sweep'`);
// force the sweep to consider this user regardless of their local hour
await db.query(
  `UPDATE workouts SET timezone_offset = $1 WHERE user_id='u-sweep'`,
  [(8 - new Date().getUTCHours()) * 60],
);
await runStreakFeaturesSweep();
const breaks = await db.query(
  `SELECT count(*)::int n FROM streak_events WHERE user_id='u-sweep' AND kind='break'`,
);
check("R8 sweep stamped NO break for a paused user", breaks[0].n, 0);

// ---------------------------------------------------------------- backdate clears stamped breaks
await mkUser("u-stamp");
await seedDays("u-stamp", 400, 4);
await refreshCurrentStreak("u-stamp");
await db.query(
  `INSERT INTO streak_events (user_id, local_date, kind, prior_streak) VALUES ('u-stamp',$1::date,'break',397)`,
  [d(3)],
);
await ips.startInjuryPause("u-stamp", d(3));
const stampLeft = await db.query(
  `SELECT count(*)::int n FROM streak_events WHERE user_id='u-stamp' AND kind='break'`,
);
check("BD backdated pause clears the stamped break", stampLeft[0].n, 0);
check("BD streak reattaches across the break", await streakOf("u-stamp"), 397);

// ---------------------------------------------------------------- RULE 9: leaderboard excludes paused
const { getLeaderboard } = await import(`${B}/services/leaderboardService.js`);
await mkUser("u-rank");
await seedDays("u-rank", 50, 1);
await refreshCurrentStreak("u-rank");
for (const [a, b] of [
  ["u-rank", "u-bridge"],
  ["u-bridge", "u-rank"],
]) {
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1,$2,'accepted')
                  ON CONFLICT DO NOTHING`,
    [a, b],
  );
}
await ips.startInjuryPause("u-bridge"); // pause the long-streak user
await refreshCurrentStreak("u-bridge");
const lb = await getLeaderboard({
  userId: "u-rank",
  metric: "streak",
  period: "all",
  limit: 20,
  offset: 0,
});
check(
  "R9 paused user absent from streak leaderboard",
  lb.entries.some((e) => e.user_id === "u-bridge"),
  false,
);
check(
  "R9 unpaused friend still ranks",
  lb.entries.some((e) => e.user_id === "u-rank"),
  true,
);

// ---------------------------------------------------------------- pure flame + payload
const { getStreakFeaturesPayload } = await import(
  `${B}/services/streakFeatureService.js`
);
const s = await getActiveStreak("u-bridge");
const payload = await getStreakFeaturesPayload("u-bridge", s.streak, s.start);
check("PF pure flame lost while paused", payload.natural_streak, false);
check(
  "PF payload exposes the active pause",
  payload.injury_pause.active !== null,
  true,
);
const natural = await getActiveStreak("u-rank");
const p2 = await getStreakFeaturesPayload(
  "u-rank",
  natural.streak,
  natural.start,
);
check("PF never-paused user keeps pure flame", p2.natural_streak, true);

// ------------------------------------------------- REGRESSIONS (codex review)
// RG1: Date.UTC takes a ZERO-BASED month. Passing the month straight through
// made month-crossing spans wrong and day-31 overflows NEGATIVE, so a user
// could be told their 30-day minimum wasn't up when it was.
await mkUser("u-cal");
await db.query(
  `INSERT INTO streak_pauses (user_id, started_on, frozen_streak)
   VALUES ('u-cal','2026-01-31'::date,120)`,
);
await db.query(
  `INSERT INTO workouts (workout_id,user_id,distance,local_date,date,timezone_offset,
     workout_type,device_end_date,calories,total_duration,source,speed_flagged,feed_role)
   VALUES ('u-cal-w','u-cal',1.2,'2026-01-30'::date,'2026-01-30'::timestamptz,0,'running',
           '2026-01-30'::timestamptz,100,600,'test',false,'daily_mile')`,
);
const calSt = await ips.getInjuryPauseStatus("u-cal");
check(
  "RG1 month-crossing pause counts days positively",
  calSt.active.paused_days > 0,
  true,
);
check(
  "RG1 Jan-31 pause expires 179 days later, not in month 13",
  calSt.active.expires_on,
  core.dateStrPlus("2026-01-31", 179),
);

// RG2: re-earn must be 90 CONSECUTIVE days, not 90 scattered qualifying days.
await mkUser("u-scatter");
await db.query(
  `INSERT INTO streak_pauses (user_id, started_on, resumed_on, frozen_streak)
   VALUES ('u-scatter',$1::date,$2::date,100)`,
  [d(400), d(300)],
);
for (let n = 300; n > 0; n -= 2) await seedDays("u-scatter", n, n); // every OTHER day
await refreshCurrentStreak("u-scatter");
const scatterSt = await ips.getInjuryPauseStatus("u-scatter");
check(
  "RG2 150 scattered days do NOT satisfy the 90-consecutive rule",
  scatterSt.eligible,
  false,
);
// The number is what proves it: counting qualifying days since the resume
// (the original bug) reports ~150 here and unlocks a second pause. Clamping to
// the live streak reports the real consecutive run, which is 1.
check(
  "RG2 re-earn meter reports the consecutive run, not the tally",
  scatterSt.reearn_progress < 5,
  true,
);

// RG3: an injury has usually already cost a day or two before the user opens
// the app, so `eligible` must reflect what a BACKDATED start would accept.
await mkUser("u-late");
await seedDays("u-late", 400, 4); // last run 4 days ago
await refreshCurrentStreak("u-late");
const lateRow = await db.query(
  `SELECT current_streak FROM users WHERE user_id='u-late'`,
);
check("RG3 live streak has already broken", lateRow[0].current_streak, 0);
const lateSt = await ips.getInjuryPauseStatus("u-late");
check(
  "RG3 still eligible via backdating",
  [lateSt.eligible, lateSt.reason],
  [true, null],
);
const lateStart = await ips.startInjuryPause("u-late", d(3));
check(
  "RG3 backdated start recovers the streak",
  lateStart.active.frozen_streak,
  397,
);

// RG4: calendar-invalid dates that satisfy the shape regex.
await throws(
  "RG4 Feb 31 rejected",
  () => ips.startInjuryPause("u-long", "2026-02-31"),
  "invalid_started_on",
);
await throws(
  "RG4 month 13 rejected",
  () => ips.startInjuryPause("u-long", "2026-13-01"),
  "invalid_started_on",
);

// RG5: the kill switch must never un-bridge an OPEN pause. With the switch on,
// callers fall to the legacy walk, which knows nothing about streak_pauses —
// and refreshCurrentStreak would then persist a frozen streak as BROKEN.
await mkUser("u-kill");
await seedDays("u-kill", 400, 40);
await db.query(
  `INSERT INTO streak_pauses (user_id, started_on, frozen_streak)
   VALUES ('u-kill',$1::date,361)`,
  [d(39)],
);
check(
  "RG5 paused streak intact with features on",
  await streakOf("u-kill"),
  361,
);
process.env.STREAK_FEATURES_DISABLED = "true";
check(
  "RG5 paused streak SURVIVES the kill switch",
  await streakOf("u-kill"),
  361,
);
check(
  "RG5 refreshCurrentStreak does not persist a break",
  await refreshCurrentStreak("u-kill"),
  361,
);
delete process.env.STREAK_FEATURES_DISABLED;

// RG6: a paused viewer must not get a ranked current_user_entry while the page
// and total_count exclude them.
const lbSelf = await getLeaderboard({
  userId: "u-bridge",
  metric: "streak",
  period: "all",
  limit: 20,
  offset: 0,
});
check(
  "RG6 paused viewer gets no ranked self entry",
  lbSelf.current_user_entry,
  null,
);

// RG7: concurrent starts race the partial unique index, not a 500.
await mkUser("u-race");
await seedDays("u-race", 400, 1);
await refreshCurrentStreak("u-race");
const raced = await Promise.allSettled([
  ips.startInjuryPause("u-race"),
  ips.startInjuryPause("u-race"),
]);
const rejected = raced.filter((r) => r.status === "rejected");
check(
  "RG7 exactly one concurrent start wins",
  raced.filter((r) => r.status === "fulfilled").length,
  1,
);
check(
  "RG7 loser gets already_paused, not a crash",
  rejected.map((r) => r.reason.message),
  ["already_paused"],
);

// RG8: ending a pause that is already past the cap is an EXPIRY, not a resume —
// otherwise a lagging sweep lets a manual end preserve an over-cap gap forever.
await mkUser("u-overcap");
await seedDays("u-overcap", 400, 200);
await db.query(
  `INSERT INTO streak_pauses (user_id, started_on, frozen_streak)
   VALUES ('u-overcap',$1::date,201)`,
  [d(199)], // starts the day after their last qualifying day, no real gap
);
await refreshCurrentStreak("u-overcap");
check(
  "RG8 over-cap pause still frozen pre-end",
  await streakOf("u-overcap"),
  201,
);
await ips.endInjuryPause("u-overcap");
const overcapRow = await db.query(
  `SELECT expired_at IS NOT NULL AS expired FROM streak_pauses WHERE user_id='u-overcap'`,
);
check(
  "RG8 manual end past the cap marks it expired",
  overcapRow[0].expired,
  true,
);
check("RG8 streak ends rather than bridging", await streakOf("u-overcap"), 0);

// RG9: on the day a streak first reaches exactly 90, a pause started today
// would freeze the run ending YESTERDAY (89) — status must not advertise it.
await mkUser("u-thresh");
await seedDays("u-thresh", 89, 0); // exactly 90 days, including today
await refreshCurrentStreak("u-thresh");
check("RG9 streak is exactly 90 today", await streakOf("u-thresh"), 90);
const threshSt = await ips.getInjuryPauseStatus("u-thresh");
check(
  "RG9 status agrees with what POST would do",
  [threshSt.eligible, threshSt.reason],
  [false, "streak_too_short"],
);
await throws(
  "RG9 POST rejects too, consistently",
  () => ips.startInjuryPause("u-thresh"),
  "streak_too_short",
);

// RG10: /streak-eras must bridge open pauses under the kill switch too, or it
// disagrees with the live streak endpoint for the same user.
process.env.STREAK_FEATURES_DISABLED = "true";
const killEras = await core.computeStreakEras("u-kill", today);
check(
  "RG10 era walk bridges the pause under the kill switch",
  killEras.eras[0].length,
  361,
);
delete process.env.STREAK_FEATURES_DISABLED;

// RG11: a token-covered most-recent day is still a streak day. Scanning only
// `workouts` made status report streak_too_short while POST would have worked.
await mkUser("u-covered");
await seedDays("u-covered", 200, 1);
await db.query(
  `INSERT INTO streak_coverage (user_id, local_date, kind) VALUES ('u-covered',$1::date,'streak_save')`,
  [d(0)],
); // today carried by a token, no workout row
await refreshCurrentStreak("u-covered");
const covSt = await ips.getInjuryPauseStatus("u-covered");
check("RG11 token-covered day keeps the CTA eligible", covSt.eligible, true);

// ---------------------------------------------------------------- legacy parity
await mkUser("u-legacy", { enrolled: false });
await seedDays("u-legacy", 30, 1);
check("LP un-enrolled user unaffected", await streakOf("u-legacy"), 30);

console.log(results.join("\n"));
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
