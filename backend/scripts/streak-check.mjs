// Streak snapshot check: the stored streak (users.current_streak +
// streak_start_date / streak_valid_through / streak_computed_at) against
// seeded histories, including the one that broke in production — a
// 2,500-day streak, which the old LIMIT-500 writer reported as exactly 500.
//
// Everything here fails silently in the product: a capped number, a friend
// list that decays a day late, a covered day that stops counting, a pause
// that un-freezes. So each shape is pinned, and a batch of random histories
// is diffed against an independent reference walk.
//
// Usage: DATABASE_URL=postgres://... node scripts/streak-check.mjs
import assert from "node:assert/strict";

const { PostgresService } = await import("../dist/services/DbService.js");
const core = await import("../dist/services/streakFeatureCore.js");
const { getActiveStreak, getStreakErasForUser } =
  await import("../dist/services/workoutService.js");
const { refreshCurrentStreak, reconcileStaleStreaks } =
  await import("../dist/services/leaderboardService.js");
const { getFriends } = await import("../dist/services/friendshipService.js");

const db = PostgresService.getInstance();

// The user's "today" derives from NOW() + their tz offset in the DB session's
// zone; every seeded user carries offset 0, so this is their today exactly.
const TODAY = (
  await db.query(`SELECT to_char(NOW()::date, 'YYYY-MM-DD') AS d`)
)[0].d;
const ago = (n) => core.dateStrMinus(TODAY, n);
const plus = (n) => core.dateStrPlus(TODAY, n);

async function cleanup() {
  await db.query(
    `DELETE FROM friendships WHERE user_id LIKE 'sc-%' OR friend_id LIKE 'sc-%'`,
  );
  await db.query(`DELETE FROM streak_coverage WHERE user_id LIKE 'sc-%'`);
  await db.query(`DELETE FROM streak_pauses WHERE user_id LIKE 'sc-%'`);
  await db.query(`DELETE FROM workouts WHERE user_id LIKE 'sc-%'`);
  await db.query(`DELETE FROM users WHERE user_id LIKE 'sc-%'`);
}

async function mkUser(id, { enrolled = false } = {}) {
  await db.query(
    `INSERT INTO users (user_id, email, apple_sub, username, first_name, streak_features_at)
     VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT (user_id) DO NOTHING`,
    [
      id,
      `${id}@sc.local`,
      `sc-sub-${id}`,
      id.replace(/-/g, "_"),
      id,
      enrolled ? new Date().toISOString() : null,
    ],
  );
}

let seq = 0;
async function seedWorkout(
  userId,
  date,
  miles,
  { deleted = false, excluded = null } = {},
) {
  await db.query(
    `INSERT INTO workouts (workout_id,user_id,distance,local_date,date,timezone_offset,
       workout_type,device_end_date,calories,total_duration,source,speed_flagged,feed_role,
       deleted_at,exclusion_reason)
     VALUES ($1,$2,$3,$4::date,$4::date,0,'walking',($4::date + interval '9 hours'),100,1200,
             'healthkit',false,'extra',$5,$6)`,
    [
      `${userId}-${date}-${++seq}`,
      userId,
      miles,
      date,
      deleted ? new Date().toISOString() : null,
      excluded,
    ],
  );
}

/** One 1.2-mile workout per day, `fromAgo` days ago through `toAgo` days ago. */
async function seedRange(userId, fromAgo, toAgo, miles = 1.2) {
  await db.query(
    `INSERT INTO workouts (workout_id,user_id,distance,local_date,date,timezone_offset,
       workout_type,device_end_date,calories,total_duration,source,speed_flagged,feed_role)
     SELECT $1 || '-r-' || d, $1, $4::float, ($2::date - d)::date, ($2::date - d)::date, 0, 'walking',
            (($2::date - d)::timestamp + interval '9 hours'), 100, 1200, 'healthkit', false, 'extra'
     FROM generate_series($3::int, $5::int) d`,
    [userId, TODAY, toAgo, miles, fromAgo],
  );
}

async function row(id) {
  const r = (
    await db.query(
      `SELECT current_streak, longest_streak,
              to_char(streak_start_date, 'YYYY-MM-DD') AS start,
              to_char(streak_valid_through, 'YYYY-MM-DD') AS valid_through,
              streak_computed_at::text AS computed_at
         FROM users WHERE user_id = $1`,
      [id],
    )
  )[0];
  return r;
}

let passed = 0;
function ok(name, got, want) {
  assert.deepEqual(got, want, name);
  passed++;
  console.log(`  ✓ ${name}`);
}

await cleanup();

// ── A. The headline: a 2,500-day streak ────────────────────────────────────
console.log("A. 2,500-day streak");
await mkUser("sc-long");
await seedRange("sc-long", 2499, 0);
ok(
  "refreshCurrentStreak reports the whole run",
  await refreshCurrentStreak("sc-long"),
  2500,
);
{
  const r = await row("sc-long");
  ok("stored current_streak", r.current_streak, 2500);
  ok("stored longest_streak ratcheted", r.longest_streak, 2500);
  ok("stored start date", r.start, ago(2499));
  ok(
    "stored valid-through = tomorrow (yesterday grace)",
    r.valid_through,
    plus(1),
  );
  ok("stored computed_at set", r.computed_at !== null, true);
}
ok("getActiveStreak reads the stored run", await getActiveStreak("sc-long"), {
  streak: 2500,
  start: ago(2499),
});
{
  const eras = await getStreakErasForUser("sc-long");
  ok("eras: one current era of 2500", eras, {
    eras: [
      {
        start_date: ago(2499),
        end_date: TODAY,
        length: 2500,
        is_current: true,
      },
    ],
    longest: 2500,
  });
}
ok(
  "streakEndingAt(today) over 2500 days",
  await core.streakEndingAt("sc-long", TODAY),
  2500,
);
ok(
  "snapshot for tomorrow still 2500 (yesterday anchor)",
  (await core.computeStreakSnapshot("sc-long", plus(1))).streak,
  2500,
);
ok(
  "snapshot for the day after reads 0",
  (await core.computeStreakSnapshot("sc-long", plus(2))).streak,
  0,
);

// ── B. Anchors ─────────────────────────────────────────────────────────────
console.log("B. anchors");
await mkUser("sc-yday");
await seedRange("sc-yday", 10, 1);
ok("run ending yesterday counts", await refreshCurrentStreak("sc-yday"), 10);
ok("…valid through today only", (await row("sc-yday")).valid_through, TODAY);
await mkUser("sc-stale");
await seedRange("sc-stale", 11, 2);
ok("run ending two days ago is 0", await refreshCurrentStreak("sc-stale"), 0);
ok("…no valid-through at 0", (await row("sc-stale")).valid_through, null);
ok("…no start at 0", (await row("sc-stale")).start, null);
ok("unknown user reads 0", await core.readStoredStreak("sc-nobody"), {
  streak: 0,
  start: undefined,
});
ok("unknown user refresh is 0", await refreshCurrentStreak("sc-nobody"), 0);

// ── C. Gaps and eras ───────────────────────────────────────────────────────
console.log("C. gaps");
await mkUser("sc-gap");
await seedRange("sc-gap", 20, 11);
await seedRange("sc-gap", 4, 0);
ok("streak is the newest run", await refreshCurrentStreak("sc-gap"), 5);
ok(
  "eras newest first, only the first current",
  await getStreakErasForUser("sc-gap"),
  {
    eras: [
      { start_date: ago(4), end_date: TODAY, length: 5, is_current: true },
      { start_date: ago(20), end_date: ago(11), length: 10, is_current: false },
    ],
    longest: 10,
  },
);

// ── D. Threshold ───────────────────────────────────────────────────────────
console.log("D. threshold");
await mkUser("sc-thresh");
for (const m of [0.4, 0.4, 0.4]) await seedWorkout("sc-thresh", TODAY, m);
await seedWorkout("sc-thresh", ago(1), 0.94);
await seedWorkout("sc-thresh", ago(2), 0.95);
ok(
  "three 0.4s make a day, 0.94 doesn't, 0.95 does",
  await refreshCurrentStreak("sc-thresh"),
  1,
);
ok(
  "eras split at the 0.94 day",
  (await getStreakErasForUser("sc-thresh")).eras.map((e) => e.length),
  [1, 1],
);

// ── E. Deleted / excluded rows don't count ─────────────────────────────────
console.log("E. deleted / excluded");
await mkUser("sc-del");
await seedRange("sc-del", 4, 2);
await seedWorkout("sc-del", ago(1), 1.2, { excluded: "vehicle_speed" });
await seedWorkout("sc-del", TODAY, 1.2, { deleted: true });
ok(
  "tombstoned + excluded days break the anchor",
  await refreshCurrentStreak("sc-del"),
  0,
);
ok(
  "…the older run is a non-current era",
  (await getStreakErasForUser("sc-del")).eras,
  [{ start_date: ago(4), end_date: ago(2), length: 3, is_current: false }],
);

// ── F. A future-dated row can't zero a live streak ─────────────────────────
console.log("F. future-dated row");
await mkUser("sc-fut");
await seedRange("sc-fut", 4, 0);
await seedWorkout("sc-fut", plus(1), 1.2);
ok(
  "tomorrow's row is ignored, not an anchor",
  await refreshCurrentStreak("sc-fut"),
  5,
);
ok("…valid through tomorrow", (await row("sc-fut")).valid_through, plus(1));

// ── G. Coverage: enrolled only, and off under the kill switch ──────────────
console.log("G. coverage");
for (const [id, enrolled] of [
  ["sc-cov", true],
  ["sc-nocov", false],
]) {
  await mkUser(id, { enrolled });
  await seedRange(id, 9, 4);
  await seedRange(id, 2, 0);
  await db.query(
    `INSERT INTO streak_coverage (user_id, local_date, kind, trigger_date)
     VALUES ($1, $2::date, 'streak_save', $3::date)`,
    [id, ago(3), ago(2)],
  );
}
ok(
  "enrolled: the covered day bridges",
  await refreshCurrentStreak("sc-cov"),
  10,
);
ok(
  "not enrolled: coverage is invisible",
  await refreshCurrentStreak("sc-nocov"),
  3,
);
process.env.STREAK_FEATURES_DISABLED = "true";
ok(
  "kill switch: enrolled user loses the bridge",
  await refreshCurrentStreak("sc-cov"),
  3,
);
delete process.env.STREAK_FEATURES_DISABLED;
ok(
  "switch off again: bridge is back",
  await refreshCurrentStreak("sc-cov"),
  10,
);
ok(
  "eras count the covered day once",
  (await getStreakErasForUser("sc-cov")).eras.map((e) => e.length),
  [10],
);

// ── H. Reads decay without a recompute ─────────────────────────────────────
console.log("H. decay");
await db.query(
  `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1,$2,'accepted'),($2,$1,'accepted')`,
  ["sc-yday", "sc-long"],
);
// Pretend the calendar moved: the stored row's valid-through is now in the past.
await db.query(
  `UPDATE users SET streak_valid_through = $2::date WHERE user_id = $1`,
  ["sc-long", ago(1)],
);
ok("readStoredStreak decays to 0", await core.readStoredStreak("sc-long"), {
  streak: 0,
  start: undefined,
});
ok("getActiveStreak decays to 0", (await getActiveStreak("sc-long")).streak, 0);
ok(
  "friends list decays it too (in SQL)",
  (await getFriends("sc-yday")).map((f) => [f.user_id, f.current_streak]),
  [["sc-long", 0]],
);
ok(
  "the hourly sweep zeroes the row",
  (await core.decayExpiredStreaks()) >= 1,
  true,
);
ok("…stored value is 0", (await row("sc-long")).current_streak, 0);
ok("…longest_streak untouched", (await row("sc-long")).longest_streak, 2500);
ok("a refresh restores it", await refreshCurrentStreak("sc-long"), 2500);
ok(
  "friends list reads the live number again",
  (await getFriends("sc-yday")).map((f) => f.current_streak),
  [2500],
);
await core.decayExpiredStreaks(); // other scripts' leftovers may expire; ours must not
ok("a valid row is not swept", (await row("sc-long")).current_streak, 2500);

// ── I. Legacy rows heal on first read / boot sweep ─────────────────────────
console.log("I. heal");
await db.query(
  `UPDATE users SET current_streak = 500, streak_start_date = NULL,
          streak_valid_through = NULL, streak_computed_at = NULL WHERE user_id = $1`,
  ["sc-long"],
);
ok(
  "a capped legacy row heals on read",
  await core.readStoredStreak("sc-long"),
  {
    streak: 2500,
    start: ago(2499),
  },
);
ok("…and is stored", (await row("sc-long")).current_streak, 2500);
await db.query(
  `UPDATE users SET current_streak = 500, streak_computed_at = NULL WHERE user_id = $1`,
  ["sc-long"],
);
// >= 1, not === 1: other scripts' seeded users may be waiting in the same set.
ok(
  "boot sweep heals every uncomputed row",
  (await core.healUncomputedStreaks()) >= 1,
  true,
);
ok("…to the real number", (await row("sc-long")).current_streak, 2500);
await core.healUncomputedStreaks();
ok(
  "sweep leaves nothing of ours uncomputed",
  (
    await db.query(
      `SELECT COUNT(*)::int AS n FROM users
        WHERE user_id LIKE 'sc-%' AND current_streak > 0 AND streak_computed_at IS NULL`,
    )
  )[0].n,
  0,
);

// ── J. Unchanged refreshes don't write ─────────────────────────────────────
console.log("J. no-op writes");
{
  const before = (await row("sc-long")).computed_at;
  await new Promise((r) => setTimeout(r, 5));
  await refreshCurrentStreak("sc-long");
  ok(
    "identical snapshot leaves computed_at alone",
    (await row("sc-long")).computed_at,
    before,
  );
  await seedWorkout("sc-long", plus(0), 0.1); // today again: same day set
  await refreshCurrentStreak("sc-long");
  ok("…even after a no-op workout", (await row("sc-long")).computed_at, before);
}

// ── K. Pauses ──────────────────────────────────────────────────────────────
console.log("K. pauses");
await mkUser("sc-pause-open", { enrolled: true });
await seedRange("sc-pause-open", 109, 10);
await db.query(
  `INSERT INTO streak_pauses (user_id, started_on, frozen_streak) VALUES ($1, $2::date, 100)`,
  ["sc-pause-open", ago(9)],
);
ok(
  "open pause: streak frozen at 100",
  await refreshCurrentStreak("sc-pause-open"),
  100,
);
ok("…never expires", (await row("sc-pause-open")).valid_through, null);
ok(
  "…still 100 a month from now",
  (await core.computeStreakSnapshot("sc-pause-open", plus(30))).streak,
  100,
);
ok("…not swept", await core.decayExpiredStreaks(), 0);
ok(
  "…eras: one current era",
  (await getStreakErasForUser("sc-pause-open")).eras,
  [{ start_date: ago(109), end_date: ago(10), length: 100, is_current: true }],
);

await mkUser("sc-pause-closed", { enrolled: true });
await seedRange("sc-pause-closed", 109, 10);
await db.query(
  `INSERT INTO streak_pauses (user_id, started_on, resumed_on, frozen_streak)
   VALUES ($1, $2::date, $3::date, 100)`,
  ["sc-pause-closed", ago(9), TODAY],
);
ok(
  "closed pause resumed today: bridged",
  await refreshCurrentStreak("sc-pause-closed"),
  100,
);
ok(
  "…valid through the resume day",
  (await row("sc-pause-closed")).valid_through,
  TODAY,
);
ok(
  "…tomorrow without a run it breaks",
  (await core.computeStreakSnapshot("sc-pause-closed", plus(1))).streak,
  0,
);
await seedWorkout("sc-pause-closed", TODAY, 1.2);
ok(
  "…a run today extends it",
  await refreshCurrentStreak("sc-pause-closed"),
  101,
);
ok(
  "…valid through tomorrow",
  (await row("sc-pause-closed")).valid_through,
  plus(1),
);

await mkUser("sc-pause-exp", { enrolled: true });
await seedRange("sc-pause-exp", 299, 200);
await seedRange("sc-pause-exp", 19, 0);
await db.query(
  `INSERT INTO streak_pauses (user_id, started_on, resumed_on, frozen_streak, expired_at)
   VALUES ($1, $2::date, $3::date, 100, NOW())`,
  ["sc-pause-exp", ago(199), ago(19)],
);
ok(
  "expired pause no longer bridges",
  await refreshCurrentStreak("sc-pause-exp"),
  20,
);
ok(
  "…eras: the rebuilt run, then the frozen one",
  (await getStreakErasForUser("sc-pause-exp")).eras,
  [
    { start_date: ago(19), end_date: TODAY, length: 20, is_current: true },
    {
      start_date: ago(299),
      end_date: ago(200),
      length: 100,
      is_current: false,
    },
  ],
);

// ── L. Random histories vs an independent reference walk ───────────────────
console.log("L. random parity");
function reference(dayMiles) {
  // dayMiles: Map<'YYYY-MM-DD', miles>; the rule as the product states it.
  const q = new Set([...dayMiles].filter(([, m]) => m >= 0.95).map(([d]) => d));
  const walk = (from) => {
    let n = 0;
    let d = from;
    while (q.has(d)) {
      n++;
      d = core.dateStrMinus(d, 1);
    }
    return { n, start: n > 0 ? core.dateStrPlus(d, 1) : undefined };
  };
  const t = walk(TODAY);
  if (t.n > 0) return { streak: t.n, start: t.start };
  const y = walk(ago(1));
  return y.n > 0
    ? { streak: y.n, start: y.start }
    : { streak: 0, start: undefined };
}
let rng = 12345;
const rand = () => (rng = (rng * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
for (let i = 0; i < 40; i++) {
  const id = `sc-rand-${i}`;
  await mkUser(id);
  const dayMiles = new Map();
  const span = 20 + Math.floor(rand() * 60);
  for (let n = 0; n < span; n++) {
    if (rand() < 0.75) {
      const d = ago(n);
      const k = rand() < 0.3 ? 2 : 1;
      for (let j = 0; j < k; j++) {
        const m = Math.round((0.3 + rand() * 1.2) * 100) / 100;
        await seedWorkout(id, d, m);
        dayMiles.set(d, Math.round(((dayMiles.get(d) ?? 0) + m) * 1000) / 1000);
      }
    }
  }
  const want = reference(dayMiles);
  const got = await refreshCurrentStreak(id);
  assert.equal(
    got,
    want.streak,
    `${id}: streak ${got} != reference ${want.streak}`,
  );
  const read = await getActiveStreak(id);
  assert.deepEqual(read, want, `${id}: stored read differs from reference`);
}
passed++;
console.log(
  "  ✓ 40 random histories match the reference walk (refresh + read)",
);

// ── M. The daily reconcile runs clean ──────────────────────────────────────
console.log("M. reconcile");
{
  // Local, not global: rows other scripts left behind may legitimately move
  // (their day can roll over between their run and this one).
  const before = (await row("sc-long")).computed_at;
  const r = await reconcileStaleStreaks();
  assert.ok(r.checked >= 10, "reconcile checked the seeded users");
  ok(
    "reconcile leaves a correct row unwritten",
    (await row("sc-long")).computed_at,
    before,
  );
  ok("…and the number stands", (await row("sc-long")).current_streak, 2500);
}

await cleanup();
await db.close();
console.log(`streak-check: all ${passed} assertions passed`);
