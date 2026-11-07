/**
 * Community Goals check.
 *
 * Rewards are permanent and the public total only rises, so a counting mistake
 * can't be quietly corrected later. Each rule is pinned on a real migrated
 * database:
 *
 *   1. Manual, deleted and excluded workouts count for nothing.
 *   2. An edited distance counts the lower recorded figure.
 *   3. Only the goal's dates count, read from each workout's local day.
 *   4. The daily cap applies per person per day.
 *   5. The stored total never falls.
 *   6. Rewards need enough qualifying days, go out once, and survive a deletion.
 *   7. The route is self-only and reports a null goal between goals.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/community-goal-check.mjs
 */
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import communityGoalRoutes from "../dist/routes/communityGoalRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import {
  DAILY_CAP_MILES,
  getCommunityGoalForUser,
  goalPace,
  grantRewards,
  refreshTotals,
} from "../dist/services/communityGoalService.js";

const db = PostgresService.getInstance();

const GOAL = "check-goal";
const BADGE = "community_check_badge";
const SMALL_BADGE = "community_check_small";
const EARNER = "cg-earner";
const SHORT = "cg-short";
const OTHER = "cg-other";
const ALL = [EARNER, SHORT, OTHER];
// High enough that the walks here can't reach it, whatever other checks left.
const TARGET = 1000000;
const TIERS = [
  { days: 1, badge_id: SMALL_BADGE, item_id: null, name: "Small" },
  { days: 3, badge_id: BADGE, item_id: "trail_cap", name: "Cap" },
];

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

// The goal surrounds today, so `getCommunityGoalForUser` serves it.
const iso = (offset) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10);
const START = iso(-25);
const END = iso(5);
const inWindow = (i) => iso(-20 + i);

let seq = 0;
async function walk(userId, day, miles, extra = {}) {
  const id = `cg-w-${++seq}`;
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset, workout_type,
                           device_end_date, calories, total_duration, source, original_distance,
                           deleted_at, exclusion_reason)
     VALUES ($1, $2, $3, $4::date, $4::date, 0, 'walking', $4::date + interval '12 hours', 100, 1200, $5, $6, $7, $8)`,
    [id, userId, miles, day, extra.source ?? "healthkit", extra.original ?? null, extra.deletedAt ?? null, extra.excluded ?? null],
  );
  return id;
}

async function cleanup() {
  await db.query(`DELETE FROM user_badges WHERE badge_id = ANY($1)`, [[BADGE, SMALL_BADGE]]);
  await db.query(`DELETE FROM badges WHERE badge_id = ANY($1)`, [[BADGE, SMALL_BADGE]]);
  await db.query(`DELETE FROM community_goals WHERE goal_id = $1`, [GOAL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1)`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1)`, [ALL]);
}

// CI's other checks leave walks in the same database, so everything here is
// measured from where the goal started.
let baseMiles = 0;
let baseWalkers = 0;
const total = async () =>
  Math.round(
    (Number((await db.query(`SELECT total_miles FROM community_goal_totals WHERE goal_id = $1`, [GOAL]))[0]?.total_miles ?? -1) -
      baseMiles) * 1000,
  ) / 1000;
const walkers = async () =>
  ((await db.query(`SELECT walkers FROM community_goal_totals WHERE goal_id = $1`, [GOAL]))[0]?.walkers ?? -1) - baseWalkers;
const hasBadge = async (u, badge = BADGE) =>
  (await db.query(`SELECT 1 FROM user_badges WHERE user_id = $1 AND badge_id = $2`, [u, badge])).length > 0;
const assistAnchor = async (u) =>
  (await db.query(`SELECT streak_assist_last_used FROM users WHERE user_id = $1`, [u]))[0]?.streak_assist_last_used ?? null;

const app = express();
app.use(express.json());
app.use(authenticateToken);
app.use("/users", communityGoalRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

try {
  await cleanup();
  for (const u of ALL) {
    await db.query(
      `INSERT INTO users (user_id, email, apple_sub, username, streak_assist_last_used) VALUES ($1, $2, $3, $4, CURRENT_DATE)`,
      [u, `${u}@example.test`, `${u}-sub`, u.replaceAll("-", "_")],
    );
  }

  // Route with nothing live.
  const token = await generateAccessToken(EARNER);
  const headers = { authorization: `Bearer ${token}` };
  const none = await fetch(`${base}/users/${EARNER}/community-goal`, { headers });
  check("no goal: 200", none.status, 200);
  check("no goal: null", (await none.json()).goal, null);
  check(
    "another person's goal read is refused",
    (await fetch(`${base}/users/${OTHER}/community-goal`, { headers })).status,
    403,
  );

  await db.query(
    `INSERT INTO badges (badge_id, category, name, description, icon, rarity, requirement, is_hidden, sort_order)
     VALUES ($1, 'competition', 'Check', 'Check', 'map', 'rare', NULL, false, 0),
            ($2, 'competition', 'Small', 'Small', 'map', 'common', NULL, false, 0)`,
    [BADGE, SMALL_BADGE],
  );
  await db.query(
    `INSERT INTO community_goals (goal_id, title, description, target_miles, starts_on, ends_on, checkpoints, reward_tiers)
     VALUES ($1, 'Check', 'Check', $5, $2::date, $3::date, $4::jsonb, $6::jsonb)`,
    [GOAL, START, END, JSON.stringify([{ percent: 0, name: "A", fact: "B" }, { percent: 99, name: "C", fact: "D" }]), TARGET, JSON.stringify(TIERS)],
  );
  const goal = { goal_id: GOAL, starts_on: START, ends_on: END, reward_tiers: TIERS, target_miles: TARGET };

  await refreshTotals(goal);
  baseMiles = await total();
  baseWalkers = await walkers();

  // 1. What doesn't count.
  await walk(OTHER, inWindow(0), 5, { source: "manual" });
  await walk(OTHER, inWindow(1), 5, { deletedAt: new Date().toISOString() });
  await walk(OTHER, inWindow(2), 5, { excluded: "vehicle_speed" });
  await refreshTotals(goal);
  check("manual, deleted and excluded count for nothing", await total(), 0);
  check("nobody walked yet", await walkers(), 0);

  // 2. Edited distance.
  await walk(OTHER, inWindow(3), 9, { source: "edited", original: 2 });
  await refreshTotals(goal);
  check("an edit counts the lower figure", await total(), 2);

  // 3. Dates.
  await walk(OTHER, iso(-30), 5);
  await refreshTotals(goal);
  check("before the goal doesn't count", await total(), 2);

  // 4. Cap, per day.
  await walk(EARNER, inWindow(0), DAILY_CAP_MILES);
  await walk(EARNER, inWindow(0), 4);
  await refreshTotals(goal);
  check("the daily cap applies across a day's workouts", await total(), 2 + DAILY_CAP_MILES);
  check("two walkers", await walkers(), 2);

  // 6. Reward days. EARNER: 3 qualifying days. SHORT: 2, plus a day too short.
  await walk(EARNER, inWindow(1), 1);
  const earnerThird = await walk(EARNER, inWindow(2), 1);
  await walk(SHORT, inWindow(0), 1);
  await walk(SHORT, inWindow(1), 1);
  await walk(SHORT, inWindow(2), 0.5);
  await refreshTotals(goal);

  const mine = await getCommunityGoalForUser(EARNER);
  check("my miles", mine.my_miles, DAILY_CAP_MILES + 2);
  check("my days", mine.my_days, 3);
  check("served goal", mine.goal.goal_id, GOAL);
  check("state", mine.goal.state, "active");
  check("a low checkpoint is reached", mine.goal.checkpoints[0].reached, true);
  check("a high checkpoint isn't", mine.goal.checkpoints[1].reached, false);

  const first = await grantRewards(goal);
  check("enough days earns it", await hasBadge(EARNER), true);
  check("too few days doesn't", await hasBadge(SHORT), false);
  check("but they earn the lower tier", await hasBadge(SHORT, SMALL_BADGE), true);
  check("a miss gives no bonus token", (await assistAnchor(EARNER)) !== null, true);
  check(
    "a day under the qualifying distance isn't a day",
    (await getCommunityGoalForUser(SHORT)).my_days,
    2,
  );
  check(
    "everyone who walked is reported, once each",
    first.walkers.filter((r) => ALL.includes(r.user_id)).map((r) => `${r.user_id}:${r.days}`).sort(),
    [`${EARNER}:3`, `${OTHER}:1`, `${SHORT}:2`],
  );
  check("a second grant does nothing", (await grantRewards(goal)).walkers, []);
  check(
    "one medal row",
    (await db.query(`SELECT COUNT(*)::int AS n FROM user_badges WHERE user_id = $1 AND badge_id = $2`, [EARNER, BADGE]))[0].n,
    1,
  );
  check("the rewards show as earned", (await getCommunityGoalForUser(EARNER)).goal.rewards.map((r) => r.earned), [true, true]);

  // Pace: expected is 26/31 of the target by now.
  const pace = goalPace({ target_miles: 3100, starts_on: START, ends_on: END }, 100, iso(0));
  check("well under a steady pace is behind", pace.status, "behind");
  check("with time left it doesn't ask yet", goalPace({ target_miles: 3100, starts_on: iso(0), ends_on: iso(30) }, 0, iso(0)).needs_more_walkers, false);
  check("near the end it asks for more walkers", pace.needs_more_walkers, true);
  check("ahead of pace is ahead", goalPace({ target_miles: 3100, starts_on: START, ends_on: END }, 3000, iso(0)).status, "ahead");
  check("miles needed per day", pace.miles_per_day_needed, Math.ceil(3000 / 6));

  // Reached: a bonus token, by clearing the anchor.
  await db.query(`UPDATE community_goals SET target_miles = 1, rewards_granted_at = NULL WHERE goal_id = $1`, [GOAL]);
  const reached = await grantRewards({ ...goal, target_miles: 1 });
  check("reaching the target is reported", reached.reached, true);
  check("everyone who walked holds a Streak Assist", await assistAnchor(EARNER), null);

  // 5 + 6. Deleting afterwards.
  const before = await total();
  await db.query(`UPDATE workouts SET deleted_at = NOW() WHERE workout_id = $1`, [earnerThird]);
  await refreshTotals(goal);
  check("the total never falls", await total(), before);
  check("the medal stays after a deletion", await hasBadge(EARNER), true);
} catch (err) {
  failures++;
  console.error("FAIL  threw:", err);
} finally {
  await cleanup().catch(() => {});
  await new Promise((resolve) => server.close(resolve));
}

if (failures) {
  console.log(`community-goal-check: FAILED — ${failures} problem(s)`);
  process.exit(1);
}
console.log("community-goal-check: OK");
process.exit(0);
