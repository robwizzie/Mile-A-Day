/**
 * Monthly Flames check — a Flamey form per calendar month, earned by a
 * PERFECT month (every day from the 1st to the last done).
 *
 *   1. a perfect month counts every day the STREAK counts: a 0.95-mile day,
 *      a 10,000-step day, or a token-covered day — mixed freely;
 *   2. one missing day (or a 0.9-mile day, or a deleted / excluded workout)
 *      means no form; Feb's 28 days and a leap year's 29 are both judged by
 *      that month's own length;
 *   3. evergreen: the FIRST perfect year is reported, any year counts, and
 *      the form is owned (ownedFlameyItems) and wearable (PUT flamey-look),
 *      while an unearned month's form is refused (400 invalid_flamey_look);
 *   4. the closet's `monthly_flames` block lists all twelve and this month's
 *      progress: days done, today done, still perfect — a gap before today
 *      breaks it, today not yet done doesn't;
 *   5. catalog ↔ MONTHLY_FLAMES agree (same ids, month unlocks 1–12).
 *
 * Usage (same env as ci-smoke):  DATABASE_URL=... node scripts/monthly-flames-check.mjs
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import userRoutes from "../dist/routes/usersRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import { FLAMEY_CATALOG } from "../dist/services/flameyCatalog.js";
import { ownedFlameyItems } from "../dist/services/flameyService.js";
import {
  MONTHLY_FLAMES,
  perfectMonths,
} from "../dist/services/monthlyFlames.js";

const db = PostgresService.getInstance();
const PERFECT = "mf-perfect"; // perfect Feb 2025 (miles), Mar 2024 (mixed), Oct 2023 + Oct 2025
const GAPPY = "mf-gappy"; // Apr 2025 minus one day; a short day; a deleted workout
const NOW = "mf-now"; // this month, perfect through yesterday
const BROKEN = "mf-broken"; // this month, missed a day before yesterday
const ALL = [PERFECT, GAPPY, NOW, BROKEN];

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

const pad = (n) => String(n).padStart(2, "0");
const daysIn = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();
const dates = (y, m, skip = []) =>
  Array.from({ length: daysIn(y, m) }, (_, i) => i + 1)
    .filter((d) => !skip.includes(d))
    .map((d) => `${y}-${pad(m)}-${pad(d)}`);

let seq = 0;
async function mile(user, date, distance = 1.05, extra = {}) {
  seq++;
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration, deleted_at, exclusion_reason)
     VALUES ($1, $2, $3, $4::date, $4::date, 0, 'walking', $4::date + time '12:00', 80, 900, $5, $6)`,
    [
      `mf-w-${seq}`,
      user,
      distance,
      date,
      extra.deleted ? new Date().toISOString() : null,
      extra.excluded ?? null,
    ],
  );
}
const steps = (user, date, n = 11000) =>
  db.query(
    `INSERT INTO daily_steps (user_id, local_date, steps, timezone_offset) VALUES ($1, $2::date, $3, 0)`,
    [user, date, n],
  );
const covered = (user, date) =>
  db.query(
    `INSERT INTO streak_coverage (user_id, local_date, kind, trigger_date) VALUES ($1, $2::date, 'streak_save', $2::date)`,
    [user, date],
  );

async function cleanup() {
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM daily_steps WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM streak_coverage WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

const app = express();
app.use(express.json());
app.use(authenticateToken);
app.use("/users", userRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;
async function call(method, p, userId, body) {
  const token = await generateAccessToken(userId);
  const res = await fetch(base + p, {
    method,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${token}`,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {}
  return { status: res.status, json };
}

try {
  await cleanup();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, first_name)
       VALUES ($1::text, $1::text, $1::text, $1::text || '@example.com', 'M')`,
      [id],
    );
  }

  // ── 5. Catalog.
  check(
    "catalog carries all twelve monthly items",
    MONTHLY_FLAMES.map((f) => {
      const item = FLAMEY_CATALOG.get(f.itemId);
      return (
        item?.unlock.kind === "month" &&
        item.unlock.month === f.month &&
        item.slot === "color"
      );
    }),
    Array(12).fill(true),
  );

  // ── 1. Perfect months, three ways of being done.
  for (const d of dates(2025, 2)) await mile(PERFECT, d); // 28 days
  const mar = dates(2024, 3);
  for (const [i, d] of mar.entries()) {
    if (i % 3 === 0) await mile(PERFECT, d);
    else if (i % 3 === 1) await steps(PERFECT, d);
    else await covered(PERFECT, d);
  }
  for (const d of dates(2023, 10)) await mile(PERFECT, d);
  for (const d of dates(2025, 10)) await mile(PERFECT, d);
  // Two half-mile walks make a done day too (summed per local day).
  await mile(PERFECT, "2024-02-10", 0.5);
  await mile(PERFECT, "2024-02-10", 0.5);

  // ── 2. Near misses.
  for (const d of dates(2025, 4, [17])) await mile(GAPPY, d); // missing the 17th
  for (const d of dates(2025, 6, [9])) await mile(GAPPY, d);
  await mile(GAPPY, "2025-06-09", 0.9); // too short
  for (const d of dates(2025, 7, [4])) await mile(GAPPY, d);
  await mile(GAPPY, "2025-07-04", 2, { deleted: true }); // deleted
  for (const d of dates(2025, 8, [8])) await mile(GAPPY, d);
  await mile(GAPPY, "2025-08-08", 2, { excluded: "duplicate" }); // a cross-app duplicate
  for (const d of dates(2024, 2)) await mile(GAPPY, d); // leap Feb: all 29

  const perfect = await perfectMonths(PERFECT);
  check(
    "perfect: Feb, Mar (mixed), Oct",
    [...perfect.keys()].sort((a, b) => a - b),
    [2, 3, 10],
  );
  check(
    "first perfect year is reported (Oct 2023, not 2025)",
    perfect.get(10),
    2023,
  );
  check("mixed miles / steps / coverage month counts", perfect.get(3), 2024);
  const gappy = await perfectMonths(GAPPY);
  check(
    "one missing / short / deleted / excluded day ⇒ no month; leap Feb counts",
    [...gappy.keys()],
    [2],
  );

  // ── 3. Ownership + wearing.
  const owned = await ownedFlameyItems(PERFECT);
  check(
    "perfect months own their forms",
    ["sweetheart", "lucky_clover", "jack_o_lantern"].map((i) => owned.has(i)),
    [true, true, true],
  );
  check(
    "…and not the rest",
    ["frostbite", "april_showers", "twinkle_lights"].some((i) => owned.has(i)),
    false,
  );
  const wear = await call("PUT", `/users/${PERFECT}/flamey-look`, PERFECT, {
    look: { color: "jack_o_lantern" },
  });
  check(
    "wear the Jack-o'-Lantern",
    [wear.status, wear.json?.look?.color],
    [200, "jack_o_lantern"],
  );
  const refuse = await call("PUT", `/users/${PERFECT}/flamey-look`, PERFECT, {
    look: { color: "frostbite" },
  });
  check(
    "an unearned month's form is refused",
    [refuse.status, refuse.json?.error],
    [400, "invalid_flamey_look"],
  );

  // ── 4. This month's progress.
  const today = new Date().toISOString().slice(0, 10); // all seeded offsets are 0 ⇒ UTC day
  const [ty, tm, td] = today.split("-").map(Number);
  const before = Array.from(
    { length: td - 1 },
    (_, i) => `${ty}-${pad(tm)}-${pad(i + 1)}`,
  );
  for (const d of before) await mile(NOW, d);
  const now = await call("GET", `/users/${NOW}/flamey-closet`, NOW);
  const cur = now.json?.monthly_flames?.current;
  const flame = MONTHLY_FLAMES.find((f) => f.month === tm);
  check(
    "closet lists all twelve months",
    now.json?.monthly_flames?.months?.length,
    12,
  );
  check(
    "current month progress (perfect so far, today pending)",
    cur && [
      cur.month,
      cur.item_id,
      cur.days_in_month,
      cur.day_of_month,
      cur.days_done,
      cur.today_done,
      cur.still_perfect,
    ],
    [tm, flame.itemId, daysIn(ty, tm), td, td - 1, false, true],
  );
  await mile(NOW, today);
  const now2 = (await call("GET", `/users/${NOW}/flamey-closet`, NOW)).json
    ?.monthly_flames?.current;
  check(
    "today done counts",
    [now2?.days_done, now2?.today_done, now2?.still_perfect],
    [td, true, true],
  );

  if (td >= 3) {
    for (const d of before.slice(1)) await mile(BROKEN, d); // missed the 1st
    const br = (await call("GET", `/users/${BROKEN}/flamey-closet`, BROKEN))
      .json?.monthly_flames?.current;
    check("a missed day before today breaks it", br?.still_perfect, false);
  } else {
    console.log("skip  (too early in the month to seed a gap)");
  }
  const forms = (await call("GET", `/users/${PERFECT}/flamey-closet`, PERFECT))
    .json?.monthly_flames?.months;
  check(
    "earned months carry their first year",
    forms?.filter((m) => m.earned).map((m) => [m.month, m.earned_year]),
    [
      [2, 2025],
      [3, 2024],
      [10, 2023],
    ],
  );
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch(() => {});
  server.close();
  await db.end?.();
}

console.log(
  failures ? `\n${failures} failure(s)` : "\nall monthly flames checks passed",
);
process.exit(failures ? 1 : 0);
