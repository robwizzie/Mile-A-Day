import { PostgresService } from "./DbService.js";
import { countedWorkoutSql } from "./mileTime.js";
import { userOffsetMinutesSql } from "./dailyResetTime.js";
import { STREAK_QUALIFYING_MILES } from "./streakFeatureCore.js";
import { grantStreakAssist } from "./streakFeatureService.js";
import {
  deviceMeasuredDistanceSql,
  deviceMeasuredWorkoutSql,
  getUserLocalToday,
} from "./workoutService.js";

const db = PostgresService.getInstance();

/**
 * Community Goals: every user's walks move one shared journey forward, and
 * walking enough days earns a limited medal and Flamey item. See
 * docs/specs/community-goals.md.
 *
 * Totals only ever leave this service as a sum and a count of walkers: no
 * name, no per-person figure but your own, and no location at any point.
 */

/** Miles one person can add per local day. */
export const DAILY_CAP_MILES = 15;
/** Under this share of a steady pace, the group is behind. */
const BEHIND_RATIO = 0.9;
const PROJECTION_MIN_DAYS = 3;
/** How close to the end a behind group starts asking people to invite friends. */
export const INVITE_NUDGE_DAYS = 10;
/** How long before it starts a goal is shown, and after it ends. */
const PREVIEW_DAYS = 14;
const ENDED_DAYS = 7;
/**
 * Hours after `ends_on` (UTC) before rewards are granted: the last time zone's
 * midnight (14h) plus 48h for walks still waiting to sync.
 */
export const COUNTING_HOURS = 24 + 14 + 48;

export interface Checkpoint {
  percent: number;
  name: string;
  fact: string;
}

/** Days walked earns the medal, and the item when there is one. */
export interface RewardTier {
  days: number;
  badge_id: string;
  item_id: string | null;
  name: string;
  rarity?: "rare" | "epic" | "legendary" | "mythic";
}

interface GoalSeed {
  goalId: string;
  title: string;
  description: string;
  targetMiles: number;
  startsOn: string;
  endsOn: string;
  checkpoints: Checkpoint[];
  rewardTiers: RewardTier[];
}

export const COMMUNITY_GOALS: readonly GoalSeed[] = [
  {
    goalId: "coast-to-coast-2026",
    title: "Coast to Coast",
    description: "Every mile we walk in December carries us across the country, together.",
    // About 80% of what the community walked in the 30 days to Nov 6, 2026
    // (3,318 eligible miles), scaled to 31 days. Also the rough width of the US.
    targetMiles: 2800,
    startsOn: "2026-12-01",
    endsOn: "2026-12-31",
    checkpoints: [
      { percent: 20, name: "Mojave Desert", fact: "Home of Death Valley, the lowest point in North America." },
      { percent: 40, name: "Rocky Mountains", fact: "The Rockies run about 3,000 miles through North America." },
      { percent: 60, name: "Mississippi River", fact: "The Mississippi runs about 2,300 miles to the Gulf of Mexico." },
      { percent: 80, name: "Appalachian Mountains", fact: "The Appalachians are among the oldest mountains on Earth." },
      { percent: 100, name: "Atlantic Ocean", fact: "Coast to coast, one walk at a time." },
    ],
    rewardTiers: [
      { days: 5, badge_id: "community_coast_to_coast_walker", item_id: "coast_compass", name: "Compass Pendant", rarity: "rare" },
      { days: 15, badge_id: "community_coast_to_coast_2026", item_id: "trail_cap", name: "Explorer Hat", rarity: "epic" },
      { days: 25, badge_id: "community_coast_to_coast_trailblazer", item_id: "trailblazer", name: "Trailblazer Flamey", rarity: "legendary" },
      { days: 31, badge_id: "community_coast_to_coast_perfect", item_id: "horizon_wings", name: "Horizon Wings", rarity: "mythic" },
    ],
  },
];

/**
 * Inserts catalog goals missing from the table. Rewards can still change until
 * the goal starts; from then on the row is what people have earned against, so
 * it's never touched.
 */
export async function seedCommunityGoals(): Promise<void> {
  try {
    for (const g of COMMUNITY_GOALS) {
      await db.query(
        `INSERT INTO community_goals
           (goal_id, title, description, target_miles, starts_on, ends_on, checkpoints, reward_tiers)
         VALUES ($1, $2, $3, $4, $5::date, $6::date, $7::jsonb, $8::jsonb)
         ON CONFLICT (goal_id) DO UPDATE SET reward_tiers = EXCLUDED.reward_tiers
           WHERE community_goals.starts_on > CURRENT_DATE
             AND community_goals.reward_tiers IS DISTINCT FROM EXCLUDED.reward_tiers`,
        [
          g.goalId,
          g.title,
          g.description,
          g.targetMiles,
          g.startsOn,
          g.endsOn,
          JSON.stringify(g.checkpoints),
          JSON.stringify(g.rewardTiers),
        ],
      );
    }
  } catch (e: any) {
    console.error("[community-goals] seed failed:", e?.message ?? e);
  }
}

/**
 * The one definition of what counts: one row per person per local day, in the
 * window, device-measured, capped. $1 and $2 are the window's first and last
 * days; `extra` narrows it further, such as to one person.
 */
function goalDaysSql(extra = ""): string {
  return `
    SELECT w.user_id, w.local_date,
           LEAST(SUM(${deviceMeasuredDistanceSql("w")}), ${DAILY_CAP_MILES}) AS miles
      FROM workouts w
     WHERE w.local_date >= $1::date AND w.local_date <= $2::date
       AND ${countedWorkoutSql("w")}
       AND ${deviceMeasuredWorkoutSql("w")}
       ${extra}
     GROUP BY w.user_id, w.local_date`;
}

/** How long a walkers-today count is reused before it's read again. */
const TODAY_CACHE_MS = 60_000;
const todayCache = new Map<string, { until: number; count: number }>();

function addDays(day: string, n: number): string {
  return new Date(Date.parse(`${day}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);
}

/**
 * How many people have added miles today, each on their OWN local day (the
 * same `local_date` their walk is credited to). Only the day either side of
 * UTC today can be anyone's today, so the read stays on a three-day slice of
 * the index. A count, never names, and computed live, so it resets daily.
 */
export async function walkersToday(goal: Pick<GoalRow, "goal_id" | "starts_on" | "ends_on">): Promise<number> {
  const hit = todayCache.get(goal.goal_id);
  if (hit && hit.until > Date.now()) return hit.count;
  const utc = new Date().toISOString().slice(0, 10);
  const from = [goal.starts_on, addDays(utc, -1)].sort()[1];
  const to = [goal.ends_on, addDays(utc, 1)].sort()[0];
  let count = 0;
  if (from <= to) {
    const rows = await db.query<{ n: number }>(
      `SELECT COUNT(DISTINCT d.user_id)::int AS n
         FROM (${goalDaysSql()}) d
        WHERE d.miles > 0
          AND d.local_date = (NOW() + (${userOffsetMinutesSql("d.user_id")} || ' minutes')::interval)::date`,
      [from, to],
    );
    count = rows[0]?.n ?? 0;
  }
  todayCache.set(goal.goal_id, { until: Date.now() + TODAY_CACHE_MS, count });
  return count;
}

/** Tests only: forget cached walkers-today counts. */
export function clearWalkersTodayCache(): void {
  todayCache.clear();
}

interface GoalRow {
  goal_id: string;
  title: string;
  description: string;
  target_miles: string;
  starts_on: string;
  ends_on: string;
  checkpoints: Checkpoint[];
  reward_tiers: RewardTier[];
  rewards_granted_at: string | null;
  total_miles: string | null;
  walkers: number | null;
}

const GOAL_SELECT = `
  SELECT g.goal_id, g.title, g.description, g.target_miles,
         to_char(g.starts_on, 'YYYY-MM-DD') AS starts_on,
         to_char(g.ends_on, 'YYYY-MM-DD') AS ends_on,
         g.checkpoints, g.reward_tiers, g.rewards_granted_at, t.total_miles, t.walkers
    FROM community_goals g
    LEFT JOIN community_goal_totals t ON t.goal_id = g.goal_id`;

/** The goal to show on a local day: the running one, else the nearest. */
async function goalForDay(day: string): Promise<GoalRow | null> {
  const rows = await db.query<GoalRow>(
    `${GOAL_SELECT}
      WHERE $1::date >= g.starts_on - ${PREVIEW_DAYS}
        AND $1::date <= g.ends_on + ${ENDED_DAYS}
      ORDER BY ($1::date BETWEEN g.starts_on AND g.ends_on) DESC, g.starts_on DESC
      LIMIT 1`,
    [day],
  );
  return rows[0] ?? null;
}

export type GoalState = "upcoming" | "active" | "counting" | "ended";

export function goalState(goal: GoalRow, today: string): GoalState {
  if (today < goal.starts_on) return "upcoming";
  if (today <= goal.ends_on) return "active";
  return goal.rewards_granted_at ? "ended" : "counting";
}

function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000);
}

export async function getCommunityGoalForUser(userId: string) {
  const today = await getUserLocalToday(userId);
  const goal = await goalForDay(today);
  if (!goal) return { goal: null, my_miles: 0, my_days: 0 };

  const badgeIds = goal.reward_tiers.map((t) => t.badge_id);
  const active = goalState(goal, today) === "active";
  const [mine, earned, walkingToday] = await Promise.all([
    db.query<{ miles: string | null; days: number }>(
      `SELECT SUM(d.miles) AS miles,
              COUNT(*) FILTER (WHERE d.miles >= ${STREAK_QUALIFYING_MILES})::int AS days
         FROM (${goalDaysSql("AND w.user_id = $3")}) d`,
      [goal.starts_on, goal.ends_on, userId],
    ),
    db.query<{ badge_id: string }>(
      `SELECT badge_id FROM user_badges WHERE user_id = $1 AND badge_id = ANY($2::text[])`,
      [userId, badgeIds],
    ),
    active ? walkersToday(goal) : Promise.resolve(null),
  ]);

  const target = Number(goal.target_miles);
  const total = Number(goal.total_miles ?? 0);
  const percent = target > 0 ? Math.min(100, Math.floor((total / target) * 100)) : 0;
  const state = goalState(goal, today);
  const daysLeft = Math.max(0, daysBetween(today, goal.ends_on) + 1);
  const held = new Set(earned.map((r) => r.badge_id));
  return {
    goal: {
      goal_id: goal.goal_id,
      title: goal.title,
      description: goal.description,
      target_miles: target,
      starts_on: goal.starts_on,
      ends_on: goal.ends_on,
      days_left: daysLeft,
      state,
      total_miles: total,
      walkers: goal.walkers ?? 0,
      /** Null outside an active goal. Additive: older apps ignore it. */
      walkers_today: walkingToday,
      percent,
      checkpoints: goal.checkpoints.map((c) => ({ ...c, reached: percent >= c.percent })),
      rewards: goal.reward_tiers.map((t) => ({ ...t, earned: held.has(t.badge_id) })),
      pace: state === "active" ? goalPace(goal, total, today, goal.walkers ?? 0) : null,
    },
    my_miles: Number(mine[0]?.miles ?? 0),
    my_days: mine[0]?.days ?? 0,
  };
}

/**
 * Where the group stands against a steady pace. Behind means more than 10%
 * under it. With time running short that turns into an ask to bring people in,
 * because the group needs more walkers, not more from each walker.
 */
export function goalPace(
  goal: Pick<GoalRow, "target_miles" | "starts_on" | "ends_on">,
  total: number,
  today: string,
  walkers = 0,
) {
  const target = Number(goal.target_miles);
  const length = daysBetween(goal.starts_on, goal.ends_on) + 1;
  const elapsed = Math.min(length, Math.max(1, daysBetween(goal.starts_on, today) + 1));
  const daysLeft = Math.max(1, daysBetween(today, goal.ends_on) + 1);
  const expected = (target * elapsed) / length;
  const behind = total < expected * BEHIND_RATIO;
  return {
    status: behind ? ("behind" as const) : total >= expected ? ("ahead" as const) : ("on_track" as const),
    miles_per_day_needed: Math.max(0, Math.ceil((target - total) / daysLeft)),
    needs_more_walkers: behind && daysLeft <= INVITE_NUDGE_DAYS,
    ...goalProjection({ target, total, length, elapsed, daysLeft, walkers, startsOn: goal.starts_on }),
  };
}

/**
 * Where today's rate lands the group, and how many more people at the average
 * walker's rate would close any gap. Nothing for the first days, when one
 * person's walk swings the rate.
 */
function goalProjection(g: {
  target: number;
  total: number;
  length: number;
  elapsed: number;
  daysLeft: number;
  walkers: number;
  startsOn: string;
}) {
  const none = { projected_miles: null, projected_finish: null, walkers_needed: null };
  if (g.elapsed < PROJECTION_MIN_DAYS || g.total <= 0) return none;
  const perDay = g.total / g.elapsed;
  const projected = Math.round(perDay * g.length);
  if (projected >= g.target) {
    const finish = new Date(Date.parse(g.startsOn) + (Math.ceil(g.target / perDay) - 1) * 86_400_000);
    return { ...none, projected_miles: projected, projected_finish: finish.toISOString().slice(0, 10) };
  }
  const shortPerDay = (g.target - g.total) / g.daysLeft - perDay;
  const perWalker = g.walkers > 0 ? perDay / g.walkers : 0;
  return {
    ...none,
    projected_miles: projected,
    walkers_needed: perWalker > 0 ? Math.max(1, Math.ceil(shortPerDay / perWalker)) : null,
  };
}

/** The running goal on a day, for anything that mentions it in passing. */
export async function activeGoalForDay(day: string): Promise<{ goal_id: string; title: string } | null> {
  const goal = await goalForDay(day);
  return goal && goalState(goal, day) === "active" ? { goal_id: goal.goal_id, title: goal.title } : null;
}

/**
 * The goal for the website: totals and the route, nothing about any person.
 * Reads the day in UTC, since a visitor has no account to take a zone from.
 */
export async function getPublicCommunityGoal() {
  const today = new Date().toISOString().slice(0, 10);
  const goal = await goalForDay(today);
  if (!goal) return { goal: null };
  const target = Number(goal.target_miles);
  const total = Number(goal.total_miles ?? 0);
  const percent = target > 0 ? Math.min(100, Math.floor((total / target) * 100)) : 0;
  const state = goalState(goal, today);
  const walkingToday = state === "active" ? await walkersToday(goal) : null;
  return {
    goal: {
      goal_id: goal.goal_id,
      title: goal.title,
      description: goal.description,
      target_miles: target,
      starts_on: goal.starts_on,
      ends_on: goal.ends_on,
      days_left: Math.max(0, daysBetween(today, goal.ends_on) + 1),
      state: goalState(goal, today),
      total_miles: total,
      walkers: goal.walkers ?? 0,
      walkers_today: walkingToday,
      percent,
      checkpoints: goal.checkpoints.map((c) => ({ percent: c.percent, name: c.name, reached: percent >= c.percent })),
      rewards: goal.reward_tiers.map((t) => ({ days: t.days, name: t.name, item_id: t.item_id, rarity: t.rarity })),
      pace: goalState(goal, today) === "active" ? goalPace(goal, total, today, goal.walkers ?? 0) : null,
    },
  };
}

/** Goals whose public numbers still move. */
export async function goalsToRefresh(): Promise<GoalRow[]> {
  return db.query<GoalRow>(
    `${GOAL_SELECT}
      WHERE g.rewards_granted_at IS NULL
        AND NOW() >= g.starts_on::timestamp - interval '14 hours'`,
  );
}

/** Recomputes a goal's total. The stored number only ever rises. */
export async function refreshTotals(goal: Pick<GoalRow, "goal_id" | "starts_on" | "ends_on">): Promise<void> {
  await db.query(
    `WITH days AS (${goalDaysSql()}),
          sums AS (
            SELECT COALESCE(SUM(miles), 0) AS total, COUNT(DISTINCT user_id)::int AS walkers FROM days
          )
     INSERT INTO community_goal_totals (goal_id, total_miles, walkers, updated_at)
     SELECT $3, total, walkers, NOW() FROM sums
     ON CONFLICT (goal_id) DO UPDATE
       SET total_miles = GREATEST(community_goal_totals.total_miles, EXCLUDED.total_miles),
           walkers = GREATEST(community_goal_totals.walkers, EXCLUDED.walkers),
           updated_at = NOW()`,
    [goal.starts_on, goal.ends_on, goal.goal_id],
  );
}

/** Goals past their counting window with rewards still to grant. */
export async function goalsDueForRewards(): Promise<GoalRow[]> {
  return db.query<GoalRow>(
    `${GOAL_SELECT}
      WHERE g.rewards_granted_at IS NULL
        AND NOW() >= g.ends_on::timestamp + interval '${COUNTING_HOURS} hours'`,
  );
}

/**
 * Claims the goal, then grants each tier's medal to everyone with enough
 * qualifying days. The claim stops a second tick granting, and a failed grant
 * releases it for a retry. If the group reached the target, everyone who walked
 * also gets a Streak Assist. Returns who took part and what they earned.
 */
export async function grantRewards(
  goal: Pick<GoalRow, "goal_id" | "starts_on" | "ends_on" | "reward_tiers" | "target_miles">,
): Promise<{ walkers: Array<{ user_id: string; days: number }>; reached: boolean }> {
  const claimed = await db.query(
    `UPDATE community_goals SET rewards_granted_at = NOW()
      WHERE goal_id = $1 AND rewards_granted_at IS NULL RETURNING goal_id`,
    [goal.goal_id],
  );
  if (claimed.length === 0) return { walkers: [], reached: false };

  try {
    for (const tier of goal.reward_tiers) {
      await db.query(
        `INSERT INTO user_badges (user_id, badge_id, earned_at)
         SELECT d.user_id, $3, NOW()
           FROM (${goalDaysSql()}) d
          WHERE d.miles >= ${STREAK_QUALIFYING_MILES}
          GROUP BY d.user_id
         HAVING COUNT(*) >= $4
         ON CONFLICT (user_id, badge_id) DO NOTHING`,
        [goal.starts_on, goal.ends_on, tier.badge_id, tier.days],
      );
    }
    const totals = await db.query<{ total_miles: string }>(
      `SELECT total_miles FROM community_goal_totals WHERE goal_id = $1`,
      [goal.goal_id],
    );
    const reached = Number(totals[0]?.total_miles ?? 0) >= Number(goal.target_miles);
    const walkers = await db.query<{ user_id: string; days: number }>(
      `SELECT d.user_id, COUNT(*) FILTER (WHERE d.miles >= ${STREAK_QUALIFYING_MILES})::int AS days
         FROM (${goalDaysSql()}) d
        GROUP BY d.user_id`,
      [goal.starts_on, goal.ends_on],
    );
    if (reached) await grantStreakAssist(walkers.map((w) => w.user_id));
    return { walkers, reached };
  } catch (error) {
    // Release the claim so the next tick tries again.
    await db.query(`UPDATE community_goals SET rewards_granted_at = NULL WHERE goal_id = $1`, [goal.goal_id]);
    throw error;
  }
}

/** Sends once per person per kind. False when it already went out. */
export async function claimPush(goalId: string, userId: string, kind: string): Promise<boolean> {
  const rows = await db.query(
    `INSERT INTO community_goal_push_log (goal_id, user_id, kind) VALUES ($1, $2, $3)
     ON CONFLICT (goal_id, user_id, kind) DO NOTHING RETURNING user_id`,
    [goalId, userId, kind],
  );
  return rows.length > 0;
}
