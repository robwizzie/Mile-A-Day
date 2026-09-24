/**
 * Badge recalibrate check — medals are judged over the WHOLE history.
 *
 *   1. POST /workouts/:id/recalibrate-streak awards what a repaired history
 *      has earned but the user doesn't hold, across categories: a BROKEN
 *      370-day streak (streak ladder up to streak_365, not streak_500), a
 *      sub-8 mile split (pace_8min, not pace_7min), a half-marathon day
 *      (daily_half), a Halloween goal day (holiday_halloween), lifetime
 *      miles, a hype given (never a self-hype) and a nudge whose log row has
 *      since been pruned (the lifetime counter);
 *   2. it answers `new_badges` = exactly the rows it inserted, is idempotent
 *      (a second run awards nothing) and NEVER revokes a medal already held;
 *   3. push behaviour: a burst above the limit is ONE summary `badge_earned`
 *      inbox row with string-valued data; a small award is one row per medal;
 *   4. the per-upload path is retroactive too: a user whose only 10-day run
 *      broke long ago gets the streak medals on their next upload;
 *   5. the retro sweep awards silently (no inbox row, is_new TRUE), is
 *      idempotent, and a targeted run never writes the global done-marker;
 *   6. revocation measures the same longest run, so it keeps what it awarded.
 *
 * Every failure here is silent in production (a medal nobody gets), so the
 * assertions are memberships and deltas on this script's own users, never
 * global counts.
 *
 * Usage (same env as ci-smoke):  DATABASE_URL=... node scripts/badge-recalibrate-check.mjs
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import express from "express";
import pg from "pg";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import workoutRoutes from "../dist/routes/workoutRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import {
  revokeUnearnedBadges,
  seedExtraBadges,
} from "../dist/services/badgeService.js";
import { logFriendNudge } from "../dist/services/pushNotificationService.js";
import { seedExtraChallenges } from "../dist/services/dailyChallengeService.js";
import {
  runRetroBadgeBackfill,
  RETRO_BADGES_BACKFILL,
} from "../dist/db/backfillRetroBadges.js";

const db = PostgresService.getInstance();
const here = path.dirname(fileURLToPath(import.meta.url));

const RC = "brc-recal"; // the repaired history
const FRIEND = "brc-friend"; // hype / nudge target
const SMALL = "brc-small"; // one medal via recalibrate
const SELFIE = "brc-selfie"; // only ever hyped themselves
const UP = "brc-upload"; // old broken run, earns on the next upload
const SWEEP = "brc-sweep"; // retro sweep target
const ALL = [RC, FRIEND, SMALL, SELFIE, UP, SWEEP];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

async function cleanup() {
  const fkTables = await db.query(
    `SELECT DISTINCT tc.table_name
       FROM information_schema.table_constraints tc
       JOIN information_schema.constraint_column_usage ccu
         ON ccu.constraint_name = tc.constraint_name
      WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'users'
        AND ccu.column_name = 'user_id'`,
  );
  for (const q of [
    `DELETE FROM user_badges WHERE user_id = ANY($1)`,
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1)`,
    `DELETE FROM notification_log WHERE user_id = ANY($1)`,
    `DELETE FROM pending_notifications WHERE user_id = ANY($1)`,
    `DELETE FROM hype_log WHERE sender_id = ANY($1) OR target_id = ANY($1)`,
    `DELETE FROM friend_nudge_log WHERE sender_id = ANY($1) OR target_id = ANY($1)`,
    `DELETE FROM workout_splits WHERE workout_id IN (SELECT workout_id FROM workouts WHERE user_id = ANY($1))`,
    `DELETE FROM workout_routes WHERE workout_id IN (SELECT workout_id FROM workouts WHERE user_id = ANY($1))`,
  ]) {
    await db.query(q, [ALL]).catch(() => {});
  }
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

const app = express();
app.use(express.json({ limit: "2mb" }));
app.use(authenticateToken);
app.use("/workouts", workoutRoutes);
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

/** A run of `days` 1-mile walks ending on `endDay` (inclusive). */
async function seedRun(user, prefix, endDay, days, dist = 1.0) {
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset, workout_type,
                           device_end_date, calories, total_duration)
     SELECT $1 || '-' || g, $2, $5, d::date, d::date, 0, 'walking', d::date + TIME '12:00' AT TIME ZONE 'UTC', 0, 1200
     FROM generate_series(0, $4 - 1) g,
          LATERAL (SELECT ($3::date - g) AS d) x`,
    [prefix, user, endDay, days, dist],
  );
}
async function seedWalk(user, id, day, dist) {
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset, workout_type,
                           device_end_date, calories, total_duration)
     VALUES ($1, $2, $3, $4::date, $4::date, 0, 'walking', ($4 || 'T12:00:00Z')::timestamptz, 0, 1800)`,
    [id, user, dist, day],
  );
}

const held = async (u) =>
  (await db.query(`SELECT badge_id FROM user_badges WHERE user_id = $1 ORDER BY badge_id`, [u])).map((r) => r.badge_id);
const badgeInbox = async (u) =>
  db.query(
    `SELECT data FROM in_app_notifications WHERE user_id = $1 AND type = 'badge_earned' ORDER BY created_at`,
    [u],
  );
async function waitFor(fn, ms = 4000) {
  const until = Date.now() + ms;
  for (;;) {
    const v = await fn();
    if (v || Date.now() > until) return v;
    await new Promise((r) => setTimeout(r, 100));
  }
}

const pgClient = new pg.Client({ connectionString: process.env.DATABASE_URL });
await pgClient.connect();

try {
  await cleanup();
  // The full canonical catalog (streak / miles / pace / daily ladders) plus
  // the v2 social + holiday rows. Both idempotent.
  await db.query(fs.readFileSync(path.join(here, "badges-seed.sql"), "utf8"));
  await seedExtraBadges();
  // What the server seeds at boot: a today-dated upload selects today's
  // challenge, and an empty catalog would throw before badges are judged.
  await seedExtraChallenges();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, first_name) VALUES ($1::text, $1::text, $1::text, $1::text || '@example.com', 'T')`,
      [id],
    );
  }

  // ── The repaired history: a 370-day run that BROKE in Jan 2025 (it spans
  // Halloween 2024), a half-marathon day, a sub-8 split, a hype given and
  // one received from themselves, a nudge whose log has been pruned.
  await seedRun(RC, "brc-run", "2025-01-10", 370);
  await seedWalk(RC, "brc-half", "2023-06-01", 13.2);
  await seedWalk(RC, "brc-fast", "2023-05-01", 1.1);
  await db.query(
    `INSERT INTO workout_splits (workout_id, split_number, split_duration, split_distance, split_pace)
     VALUES ('brc-fast', 1, 450, 1.0, 450)`,
  );
  await db.query(
    `INSERT INTO hype_log (sender_id, target_id) VALUES ($1, $2), ($1, $1)`,
    [RC, FRIEND],
  );
  await logFriendNudge(RC, FRIEND);
  check(
    "a nudge bumps the lifetime counter in the same statement",
    (await db.query(`SELECT nudges_sent_total FROM users WHERE user_id = $1`, [RC]))[0].nudges_sent_total,
    1,
  );
  // cleanupNotificationLogs prunes after 7 days — simulate it.
  await db.query(`DELETE FROM friend_nudge_log WHERE sender_id = $1`, [RC]);
  // A medal the recount would NOT grant: recalibrate must never take it.
  await db.query(`INSERT INTO user_badges (user_id, badge_id) VALUES ($1, 'miles_2500')`, [RC]);

  // ── 1+2. Recalibrate.
  const before = new Set(await held(RC));
  let r = await call("POST", `/workouts/${RC}/recalibrate-streak`, RC);
  check("recalibrate → 200", r.status, 200);
  check("streak still answered", typeof r.json?.streak, "number");
  const newBadges = r.json?.new_badges ?? [];
  const after = await held(RC);
  const inserted = after.filter((b) => !before.has(b)).sort();
  check("new_badges is exactly what was inserted", [...newBadges].sort(), inserted);
  for (const id of [
    "consistency_3",
    "streak_7",
    "streak_100",
    "streak_365",
    "special_first_week",
    "special_first_mile",
    "miles_250",
    "pace_8min",
    "daily_half",
    "holiday_halloween",
    "hype_1",
    "nudge_1",
  ]) {
    check(`recalibrate awards ${id}`, newBadges.includes(id), true);
  }
  for (const id of ["streak_500", "pace_7min", "daily_marathon", "hype_25"]) {
    check(`recalibrate does NOT award ${id}`, after.includes(id), false);
  }
  check("an existing medal is never revoked", after.includes("miles_2500"), true);
  const snap = (
    await db.query(`SELECT progress_snapshot FROM user_badges WHERE user_id = $1 AND badge_id = 'streak_365'`, [RC])
  )[0]?.progress_snapshot;
  check("award is traceable to the recalibrate", snap?.source, "recalibrate");

  // ── 3. Push: one summary row for the burst, string-valued data.
  const rcInbox = await waitFor(async () => {
    const rows = await badgeInbox(RC);
    return rows.length > 0 ? rows : null;
  });
  check("burst → ONE badge_earned inbox row", rcInbox?.length ?? 0, 1);
  const data = rcInbox?.[0]?.data ?? {};
  check("summary carries the count", data.count, String(newBadges.length));
  check("summary routes to a medal it awarded", newBadges.includes(data.badge_id), true);
  check("summary source", data.source, "recalibrate");
  check("every data value is a string", Object.values(data).every((v) => typeof v === "string"), true);

  // Idempotent.
  r = await call("POST", `/workouts/${RC}/recalibrate-streak`, RC);
  check("second recalibrate awards nothing", r.json?.new_badges, []);
  check("second recalibrate leaves the shelf alone", await held(RC), after);
  await new Promise((res) => setTimeout(res, 300));
  check("second recalibrate pushes nothing", (await badgeInbox(RC)).length, 1);

  // Revocation measures the same longest run → keeps the ladder it awarded.
  const revoked = await revokeUnearnedBadges(RC);
  check("revocation keeps the historical streak ladder", revoked.filter((b) => b.startsWith("streak_") || b.startsWith("consistency_")), []);

  // ── Self-hypes never earn, even on an all-history recount.
  await db.query(`INSERT INTO hype_log (sender_id, target_id) VALUES ($1, $1)`, [SELFIE]);
  r = await call("POST", `/workouts/${SELFIE}/recalibrate-streak`, SELFIE);
  check("a self-hype earns no hype medal", (r.json?.new_badges ?? []).includes("hype_1"), false);

  // ── A small award is one push per medal.
  await seedWalk(SMALL, "brc-small-1", "2025-03-03", 1.0);
  r = await call("POST", `/workouts/${SMALL}/recalibrate-streak`, SMALL);
  const smallNew = r.json?.new_badges ?? [];
  check("small award → special_first_mile", smallNew.includes("special_first_mile"), true);
  check("small award is within the per-medal limit", smallNew.length >= 1 && smallNew.length <= 3, true);
  const smallInbox = await waitFor(async () => {
    const rows = await badgeInbox(SMALL);
    return rows.length >= smallNew.length ? rows : null;
  });
  check("one badge_earned row per medal", (smallInbox ?? []).length, smallNew.length);
  check("per-medal rows carry no summary count", (smallInbox ?? []).every((x) => x.data?.count === undefined), true);

  // ── 4. The upload path is all-history too: a 10-day run that broke in
  // 2024, then a fresh walk today.
  await seedRun(UP, "brc-up-old", "2024-02-20", 10);
  const today = new Date().toISOString().slice(0, 10);
  r = await call("POST", `/workouts/${UP}/upload`, UP, [
    {
      workoutId: "brc-up-today",
      distance: 0.3,
      localDate: today,
      date: `${today}T12:00:00.000Z`,
      timezoneOffset: 0,
      workoutType: "walking",
      deviceEndDate: new Date().toISOString(),
      calories: 10,
      totalDuration: 400,
      splits: [],
    },
  ]);
  check("upload → 200", r.status, 200);
  const upBadges = (r.json?.newlyEarnedBadges ?? []).map((b) => b.badgeId);
  check("upload awards the broken run's streak_7", upBadges.includes("streak_7"), true);
  check("upload awards the broken run's streak_10", upBadges.includes("streak_10"), true);
  check("upload doesn't invent streak_14", upBadges.includes("streak_14"), false);

  // ── 5. Retro sweep: silent, idempotent, targeted runs leave the marker.
  await seedRun(SWEEP, "brc-sw", "2023-11-05", 8); // spans Halloween 2023
  const markerBefore = (await db.query(`SELECT 1 FROM maintenance_runs WHERE name = $1`, [RETRO_BADGES_BACKFILL])).length;
  let sw = await runRetroBadgeBackfill(pgClient, { force: true, onlyUserIds: [SWEEP] });
  const swept = await held(SWEEP);
  check("sweep visited the one user", sw.users, 1);
  check("sweep awarded what it reports", swept.length, sw.awarded);
  check("sweep awards the broken run's streak_7", swept.includes("streak_7"), true);
  check("sweep awards holiday_halloween", swept.includes("holiday_halloween"), true);
  check("sweep is silent (no inbox row)", (await badgeInbox(SWEEP)).length, 0);
  check(
    "sweep leaves is_new TRUE",
    (await db.query(`SELECT bool_and(is_new) AS n FROM user_badges WHERE user_id = $1`, [SWEEP]))[0].n,
    true,
  );
  check(
    "sweep awards are traceable",
    (await db.query(`SELECT DISTINCT progress_snapshot->>'source' AS s FROM user_badges WHERE user_id = $1`, [SWEEP])).map((x) => x.s),
    ["retro_sweep"],
  );
  sw = await runRetroBadgeBackfill(pgClient, { force: true, onlyUserIds: [SWEEP] });
  check("sweep is idempotent", sw.awarded, 0);
  check(
    "a targeted sweep never writes the done-marker",
    (await db.query(`SELECT 1 FROM maintenance_runs WHERE name = $1`, [RETRO_BADGES_BACKFILL])).length,
    markerBefore,
  );
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch((e) => console.error("cleanup failed:", e.message));
  await pgClient.end().catch(() => {});
  server.close();
  await db.close?.().catch?.(() => {});
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nbadge-recalibrate-check: all passed");
process.exit(0);
