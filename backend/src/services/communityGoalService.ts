import { PostgresService } from "./DbService.js";
import { countedWorkoutSql } from "./mileTime.js";
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
      { days: 5, badge_id: "community_coast_to_coast_walker", item_id: null, name: "Coast Walker medal" },
      { days: 15, badge_id: "community_coast_to_coast_2026", item_id: "trail_cap", name: "Trail Cap" },
      { days: 25, badge_id: "community_coast_to_coast_trailblazer", item_id: "trailblazer", name: "Trailblazer Flamey" },
    ],
  },
];

/**
 * Inserts catalog goals missing from the table. Never updates a row: once a
 * goal exists, the row is what people have seen and earned against.
 */
export async function seedCommunityGoals(): Promise<void> {
  try {
    for (const g of COMMUNITY_GOALS) {
      await db.query(
        `INSERT INTO community_goals
           (goal_id, title, description, target_miles, starts_on, ends_on, checkpoints, reward_tiers)
         VALUES ($1, $2, $3, $4, $5::date, $6::date, $7::jsonb, $8::jsonb)
         ON CONFLICT (goal_id) DO NOTHING`,
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
  const [mine, earned] = await Promise.all([
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
      percent,
      checkpoints: goal.checkpoints.map((c) => ({ ...c, reached: percent >= c.percent })),
      rewards: goal.reward_tiers.map((t) => ({ ...t, earned: held.has(t.badge_id) })),
      pace: state === "active" ? goalPace(goal, total, today) : null,
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
