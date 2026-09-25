/**
 * Flamey profile check — his NAME, saved OUTFITS, and HOW a medal was earned.
 *
 *   1. `PUT /users/:id/flamey-name`: trim + collapse, grapheme-counted length
 *      (20; an emoji family is ONE), emoji allowed, control chars/markup
 *      rejected, the blocklist (incl. leetspeak/spacing), `null` resets; 403
 *      for someone else's row. Served in the friends-only `flamey` block
 *      (friend + self, never a stranger, never on the top-level row) and in
 *      `GET …/flamey-closet`.
 *   2. `GET/PUT /users/:id/flamey-outfits` (self): replace semantics, ids +
 *      created_at stable across a PUT that sends them back, max 5, the
 *      `invalid_flamey_look` rules per entry, moderated names, whole-second
 *      ISO timestamps, an unowned item DROPPED at read after the medal goes
 *      (owned_ok:false) with the row untouched; also inside the closet.
 *   3. `earned_detail` on `GET /users/:id/badges` for a seeded history across
 *      streak / miles / pace / daily / holiday / special / challenge / ghost /
 *      a count medal, owner voice vs friend voice.
 *   4. Bounded: the whole list's details cost the same handful of queries for
 *      60 medals as for 8 (a query counter on the shared pool wrapper).
 *
 * Usage (same env as ci-smoke):  DATABASE_URL=... node scripts/flamey-profile-check.mjs
 */
import express from "express";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import userRoutes from "../dist/routes/usersRoutes.js";
import badgesRoutes from "../dist/routes/badgesRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import { seedExtraBadges, getUserBadges } from "../dist/services/badgeService.js";
import { earnedDetailsFor } from "../dist/services/badgeEarnedDetail.js";
import { refreshCurrentStreak } from "../dist/services/leaderboardService.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const db = PostgresService.getInstance();

const OWNER = "fp-owner";
const FRIEND = "fp-friend";
const STRANGER = "fp-stranger";
const ALL = [OWNER, FRIEND, STRANGER];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

async function cleanup() {
  await db.query(`DELETE FROM workout_splits WHERE workout_id LIKE 'fp-%'`).catch(() => {});
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
  for (const t of ["workouts", "user_challenge_completions", "user_badges", "friendships"]) {
    await db.query(`DELETE FROM ${t} WHERE user_id = ANY($1)`, [ALL]).catch(() => {});
  }
  await db.query(`DELETE FROM friendships WHERE friend_id = ANY($1)`, [ALL]).catch(() => {});
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

const app = express();
app.use(express.json({ limit: "2mb" }));
app.use(authenticateToken);
app.use("/users", userRoutes);
app.use("/users", badgesRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

async function call(method, p, userId, body) {
  const token = await generateAccessToken(userId);
  const res = await fetch(base + p, {
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

const grant = (userId, badgeId, earnedAt = "2025-11-06T15:00:00Z", trigger = null) =>
  db.query(
    `INSERT INTO user_badges (user_id, badge_id, earned_at, triggering_workout_id) VALUES ($1, $2, $3::timestamptz, $4)
     ON CONFLICT (user_id, badge_id) DO UPDATE SET earned_at = EXCLUDED.earned_at, triggering_workout_id = EXCLUDED.triggering_workout_id`,
    [userId, badgeId, earnedAt, trigger],
  );

async function workout(id, day, miles, type = "walking", extra = {}) {
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset, workout_type,
                           device_end_date, calories, total_duration, ghost_margin_seconds)
     VALUES ($1, $2, $3, $4::date, $4::date, 0, $5, ($4 || 'T12:00:00Z')::timestamptz, 0, 1800, $6)`,
    [id, OWNER, miles, day, type, extra.ghost ?? null],
  );
}

const ISO_SECONDS = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/;

try {
  await cleanup();
  await db.query(fs.readFileSync(path.join(here, "badges-seed.sql"), "utf8"));
  await seedExtraBadges();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, first_name) VALUES ($1::text, $1::text, $1::text, $1::text || '@example.com', 'T')`,
      [id],
    );
  }
  await db.query(`UPDATE users SET dashboard_style = 'fun', goal_miles = 1 WHERE user_id = ANY($1)`, [ALL]);
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted')`,
    [OWNER, FRIEND],
  );

  // ── 1. Flamey's name.
  const putName = (name, as = OWNER) => call("PUT", `/users/${OWNER}/flamey-name`, as, { name });
  let r = await putName("Sparky");
  check("name saves", [r.status, r.json], [200, { name: "Sparky" }]);
  r = await putName("  Blaze    Jr  ");
  check("trimmed + collapsed", r.json?.name, "Blaze Jr");
  r = await putName("🔥 Fuego 🔥");
  check("emoji allowed", [r.status, r.json?.name], [200, "🔥 Fuego 🔥"]);
  r = await putName("O’Flame-y. Go!");
  check("punctuation, smart apostrophe folded", [r.status, r.json?.name], [200, "O'Flame-y. Go!"]);
  r = await putName("👨‍👩‍👧".repeat(20));
  check("20 grapheme clusters (ZWJ families) fit", r.status, 200);
  r = await putName("A".repeat(21));
  check("21 chars → too_long", [r.status, r.json], [400, { error: "invalid_flamey_name", reason: "too_long" }]);
  r = await putName("   ");
  check("blank → empty", [r.status, r.json?.reason], [400, "empty"]);
  r = await putName(42);
  check("non-string → empty", [r.status, r.json?.reason], [400, "empty"]);
  r = await putName("Spark\nPlug");
  check("newline → characters", [r.status, r.json?.reason], [400, "characters"]);
  r = await putName("<b>Hi</b>");
  check("markup → characters", [r.status, r.json?.reason], [400, "characters"]);
  r = await putName("Fuck");
  check("blocked word → not_allowed", [r.status, r.json?.reason], [400, "not_allowed"]);
  r = await putName("sh1t head");
  check("leetspeak → not_allowed", [r.status, r.json?.reason], [400, "not_allowed"]);
  r = await putName("F u c k");
  check("spaced out → not_allowed", [r.status, r.json?.reason], [400, "not_allowed"]);
  r = await putName("Therapist Cassie");
  check("innocent words that contain short terms pass", [r.status, r.json?.name], [200, "Therapist Cassie"]);
  r = await call("PUT", `/users/${OWNER}/flamey-name`, FRIEND, { name: "Hacked" });
  check("someone else's row → 403", r.status, 403);
  r = await call("PUT", `/users/${OWNER}/flamey-name`, OWNER, {});
  check("missing name → 400", r.status, 400);
  r = await putName("Sparky");
  r = await call("GET", `/users/${OWNER}`, FRIEND);
  check("friend sees the name in the flamey block", r.json?.flamey?.name, "Sparky");
  check("…never on the top-level row", "flamey_name" in (r.json ?? {}), false);
  r = await call("GET", `/users/${OWNER}`, OWNER);
  check("self sees it", r.json?.flamey?.name, "Sparky");
  r = await call("GET", `/users/${OWNER}`, STRANGER);
  check("stranger: block disabled, no name", [r.json?.flamey, "flamey_name" in (r.json ?? {})], [{ enabled: false }, false]);
  r = await call("GET", `/users/${OWNER}/flamey-closet`, OWNER);
  check("closet carries name", r.json?.name, "Sparky");
  r = await putName(null);
  check("null resets", [r.status, r.json], [200, { name: null }]);
  r = await call("GET", `/users/${OWNER}`, FRIEND);
  check("friend sees null after reset", r.json?.flamey?.name, null);
  await putName("Sparky");

  // ── 2. Outfits.
  await grant(OWNER, "streak_7"); // ruby
  await grant(OWNER, "miles_25"); // ball_cap
  await grant(OWNER, "pace_10min"); // racing_flats
  const OUT = (id) => `/users/${id}/flamey-outfits`;
  r = await call("GET", OUT(OWNER), OWNER);
  check("empty list", [r.status, r.json], [200, { outfits: [] }]);
  r = await call("PUT", OUT(OWNER), OWNER, {
    outfits: [
      { name: "Race day", look: { feet: "racing_flats", head: "ball_cap" } },
      { name: "  Red   one ", look: { color: "ruby", eyes: null } },
    ],
  });
  check("PUT → 200 two outfits", [r.status, r.json?.outfits?.length], [200, 2]);
  const [raceDay, redOne] = r.json?.outfits ?? [];
  check("canonical look + order", [raceDay?.name, raceDay?.look, redOne?.name, redOne?.look], [
    "Race day",
    { head: "ball_cap", feet: "racing_flats" },
    "Red one",
    { color: "ruby", eyes: null },
  ]);
  check("uuid ids", [raceDay?.id, redOne?.id].every((id) => /^[0-9a-f-]{36}$/.test(id ?? "")), true);
  check("whole-second ISO timestamps", [raceDay?.created_at, raceDay?.updated_at].every((t) => ISO_SECONDS.test(t ?? "")), true);
  check("owned_ok true", [raceDay?.owned_ok, redOne?.owned_ok], [true, true]);
  r = await call("GET", OUT(OWNER), OWNER);
  check("GET returns the same list", r.json?.outfits?.map((o) => o.id), [raceDay?.id, redOne?.id]);
  r = await call("GET", `/users/${OWNER}/flamey-closet`, OWNER);
  check("closet carries outfits", r.json?.outfits?.map((o) => o.name), ["Race day", "Red one"]);

  await db.query(`UPDATE flamey_outfits SET created_at = '2025-01-02T03:04:05Z', updated_at = '2025-01-02T03:04:05Z' WHERE user_id = $1`, [OWNER]);
  r = await call("PUT", OUT(OWNER), OWNER, {
    outfits: [
      { id: redOne?.id, name: "Red one", look: { color: "ruby", eyes: null } }, // unchanged, moved first
      { id: raceDay?.id, name: "Race day v2", look: { feet: "racing_flats" } }, // edited
      { id: "not-a-uuid", name: "Bare", look: null }, // new
    ],
  });
  const second = r.json?.outfits ?? [];
  check("replace: order + ids stable", second.map((o) => o.id).slice(0, 2), [redOne?.id, raceDay?.id]);
  check("new entry gets a fresh id", !!second[2]?.id && second[2].id !== "not-a-uuid", true);
  check("created_at kept across PUT", second.slice(0, 2).map((o) => o.created_at), ["2025-01-02T03:04:05Z", "2025-01-02T03:04:05Z"]);
  check("updated_at moves only for the edited one", [second[0]?.updated_at === "2025-01-02T03:04:05Z", second[1]?.updated_at !== "2025-01-02T03:04:05Z"], [true, true]);
  check("null look → basic (null)", second[2]?.look, null);

  r = await call("PUT", OUT(OWNER), OWNER, { outfits: Array.from({ length: 6 }, (_, i) => ({ name: `O${i}`, look: null })) });
  check("6 outfits → 400 too_many_outfits", [r.status, r.json?.error], [400, "too_many_outfits"]);
  r = await call("PUT", OUT(OWNER), OWNER, { outfits: [{ name: "Ok", look: null }, { name: "Crown", look: { head: "crown" } }] });
  check("unowned item → 400 invalid_flamey_look", [r.status, r.json], [400, { error: "invalid_flamey_look", detail: "head:crown", index: 1 }]);
  r = await call("PUT", OUT(OWNER), OWNER, { outfits: [{ name: "Ok", look: { hat: "ball_cap" } }] });
  check("unknown slot → 400", [r.status, r.json?.detail], [400, "hat:ball_cap"]);
  r = await call("PUT", OUT(OWNER), OWNER, { outfits: [{ name: "b1tch", look: null }] });
  check("blocked outfit name → 400", [r.status, r.json], [400, { error: "invalid_outfit_name", reason: "not_allowed", index: 0 }]);
  r = await call("PUT", OUT(OWNER), OWNER, { outfits: [{ name: "x".repeat(25), look: null }] });
  check("25-char outfit name → too_long", [r.status, r.json?.reason], [400, "too_long"]);
  r = await call("GET", OUT(OWNER), OWNER);
  check("rejections wrote nothing", r.json?.outfits?.map((o) => o.name), ["Red one", "Race day v2", "Bare"]);
  r = await call("GET", OUT(OWNER), FRIEND);
  check("GET outfits is self-only → 403", r.status, 403);
  r = await call("PUT", OUT(OWNER), FRIEND, { outfits: [] });
  check("PUT outfits is self-only → 403", r.status, 403);

  // A medal goes: its item drops at READ, the row keeps it.
  await db.query(`DELETE FROM user_badges WHERE user_id = $1 AND badge_id = 'streak_7'`, [OWNER]);
  r = await call("GET", OUT(OWNER), OWNER);
  check("revoked item dropped at read", [r.json?.outfits?.[0]?.look, r.json?.outfits?.[0]?.owned_ok], [{ eyes: null }, false]);
  check("others still owned_ok", r.json?.outfits?.slice(1).map((o) => o.owned_ok), [true, true]);
  const stored = await db.query(`SELECT look FROM flamey_outfits WHERE id = $1`, [redOne?.id]);
  check("stored row untouched", stored[0]?.look?.color, "ruby");
  r = await call("PUT", OUT(OWNER), OWNER, { outfits: [] });
  check("empty list clears", [r.status, r.json], [200, { outfits: [] }]);
  await db.query(`DELETE FROM user_badges WHERE user_id = $1`, [OWNER]);

  // ── 3. earned_detail over a seeded history (all dates UTC, offset 0).
  // Walks Oct 25 → Nov 5 2025 (12 days, a 12-day streak): 1.0 mi a day,
  // except Halloween (2.3 mi walked) and Nov 2 (a 13.4 mi RUN with a 7:42
  // split). Oct 26's walk has an 11:40 split. Nov 4 beat a ghost by 52 s.
  const days = [];
  for (let i = 0; i < 12; i++) {
    const d = new Date(Date.UTC(2025, 9, 25 + i)).toISOString().slice(0, 10);
    days.push(d);
  }
  for (const day of days) {
    if (day === "2025-10-31") await workout(`fp-${day}`, day, 2.3);
    else if (day === "2025-11-02") await workout(`fp-${day}`, day, 13.4, "running");
    else if (day === "2025-11-04") await workout(`fp-${day}`, day, 1.0, "walking", { ghost: 52 });
    else await workout(`fp-${day}`, day, 1.0);
  }
  await db.query(
    `INSERT INTO workout_splits (workout_id, split_number, split_duration, split_distance, split_pace)
     VALUES ('fp-2025-11-02', 1, 462, 1.0, 462), ('fp-2025-11-02', 2, 470, 1.0, 470), ('fp-2025-10-26', 1, 700, 1.0, 700)`,
  );
  await db.query(fs.readFileSync(path.join(here, "daily-challenges-seed.sql"), "utf8"));
  await db.query(
    `INSERT INTO user_challenge_completions (user_id, local_date, challenge_key)
     VALUES ($1, '2025-10-26', 'beat_your_pace'), ($1, '2025-10-28', 'double_down')`,
    [OWNER],
  );
  await refreshCurrentStreak(OWNER);

  await grant(OWNER, "streak_7", "2025-11-06T15:00:00Z");
  await grant(OWNER, "streak_10", "2025-11-06T15:00:00Z");
  await grant(OWNER, "miles_25", "2025-11-06T15:00:00Z");
  await grant(OWNER, "pace_8min", "2025-11-02T20:00:00Z", "fp-2025-11-02");
  await grant(OWNER, "pace_12min", "2025-10-27T09:00:00Z");
  await grant(OWNER, "daily_2", "2025-10-31T20:00:00Z");
  await grant(OWNER, "daily_half", "2025-11-02T20:00:00Z");
  await grant(OWNER, "holiday_halloween", "2025-10-31T20:00:00Z");
  await grant(OWNER, "special_first_mile", "2025-10-25T20:00:00Z");
  await grant(OWNER, "special_first_week", "2025-11-06T15:00:00Z");
  await grant(OWNER, "challenge_1", "2025-10-26T20:00:00Z");
  await grant(OWNER, "ghost_margin_15", "2025-11-04T20:00:00Z");
  await grant(OWNER, "hype_1", "2025-11-06T15:00:00Z");

  r = await call("GET", `/users/${OWNER}/badges`, OWNER);
  const det = Object.fromEntries((r.json?.badges ?? []).map((b) => [b.badgeId, b.earned_detail]));
  const brief = (x) => x && [x.summary, x.date, x.value, x.unit, x.workout_id];
  check("streak_7", brief(det.streak_7), ["You reached a 7-day streak", "2025-10-31", "7", "days", null]);
  check("streak_10", brief(det.streak_10), ["You reached a 10-day streak", "2025-11-03", "10", "days", null]);
  check("miles_25", brief(det.miles_25), ["You passed 25 lifetime miles", "2025-11-05", "25", "mi", null]);
  check("pace_8min (triggering run)", [...brief(det.pace_8min), det.pace_8min?.value_seconds], [
    "You ran a 7:42 mile", "2025-11-02", "7:42", "min/mi", "fp-2025-11-02", 462,
  ]);
  check("pace_12min (on/before the award: the 11:40 walk)", brief(det.pace_12min), [
    "You walked an 11:40 mile", "2025-10-26", "11:40", "min/mi", "fp-2025-10-26",
  ]);
  check("daily_2 (first day ≥ 2)", brief(det.daily_2), ["You walked 2.3 mi in one day", "2025-10-31", "2.3", "mi", "fp-2025-10-31"]);
  check("daily_half (the run)", brief(det.daily_half), ["You ran 13.4 mi in one day", "2025-11-02", "13.4", "mi", "fp-2025-11-02"]);
  check("holiday_halloween", brief(det.holiday_halloween), [
    "You walked 2.3 mi on Halloween 2025", "2025-10-31", "2.3", "mi", "fp-2025-10-31",
  ]);
  check("special_first_mile", brief(det.special_first_mile), ["You walked your first mile", "2025-10-25", "1", "mi", null]);
  check("special_first_week", brief(det.special_first_week), ["A full week of miles", "2025-10-31", "7", "days", null]);
  check("challenge_1 (1st completion's day)", brief(det.challenge_1), [
    "You completed your first daily challenge", "2025-10-26", "1", "challenges", null,
  ]);
  check("ghost_margin_15", brief(det.ghost_margin_15), ["You beat a ghost by 52s", "2025-11-04", "52", "sec", "fp-2025-11-04"]);
  check("hype_1 (count medal, award's local day)", brief(det.hype_1), [
    "You hyped a friend for the first time", "2025-11-06", "1", "hype", null,
  ]);
  check("existing fields untouched", Object.keys(r.json?.badges?.[0] ?? {}).includes("earnedAt"), true);

  r = await call("GET", `/users/${OWNER}/badges`, FRIEND);
  const fdet = Object.fromEntries((r.json?.badges ?? []).map((b) => [b.badgeId, b.earned_detail?.summary]));
  check("friend voice", [fdet.pace_8min, fdet.challenge_1, fdet.streak_7, fdet.special_first_week], [
    "Ran a 7:42 mile", "Completed their first daily challenge", "Reached a 7-day streak", "A full week of miles",
  ]);
  r = await call("GET", `/users/${OWNER}/badges`, STRANGER);
  check("stranger still 403 on badges", r.status, 403);

  // ── 4. Bounded: count statements through the shared wrapper.
  const origQuery = db.query.bind(db);
  let queries = 0;
  db.query = (...args) => {
    queries++;
    return origQuery(...args);
  };
  const few = await getUserBadges(OWNER);
  queries = 0;
  await earnedDetailsFor(OWNER, few, "self");
  const fewQueries = queries;
  const catalog = await origQuery(`SELECT badge_id FROM badges WHERE category <> 'holiday' ORDER BY sort_order LIMIT 60`);
  for (const { badge_id } of catalog) await grant(OWNER, badge_id);
  const many = await getUserBadges(OWNER);
  queries = 0;
  const t0 = Date.now();
  const manyDetails = await earnedDetailsFor(OWNER, many, "self");
  const ms = Date.now() - t0;
  const manyQueries = queries;
  db.query = origQuery;
  check("≥ 60 medals held", many.length >= 60, true);
  check("every medal has a detail", [...manyDetails.values()].filter((v) => v === null).length, 0);
  check(`bounded queries (${fewQueries} for ${few.length} medals, ${manyQueries} for ${many.length})`, manyQueries <= 20 && manyQueries <= fewQueries + 4, true);
  check(`timing sane (${ms} ms)`, ms < 3000, true);
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch((e) => console.error("cleanup failed:", e.message));
  server.close();
  await db.close?.();
}

if (failures) {
  console.error(`\nflamey-profile-check: ${failures} failure(s)`);
  process.exit(1);
}
console.log("\nflamey-profile-check: all passed");
process.exit(0);
