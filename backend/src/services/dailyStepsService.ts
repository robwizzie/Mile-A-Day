import { PostgresService } from "./DbService.js";
import { evaluateWeeklyChallengeForUser } from "./weeklyChallengeService.js";
import {
  STREAK_QUALIFYING_STEPS,
  computeStreakEras,
} from "./streakFeatureCore.js";
import {
  refreshCurrentStreak,
  ratchetLongestStreak,
} from "./leaderboardService.js";
import { refundEarnedCoverage } from "./streakFeatureService.js";
import { evaluateSocialBadgesForUser } from "./badgeService.js";
import { getUserLocalToday } from "./workoutService.js";

const db = PostgresService.getInstance();

export interface UpsertDailyStepsResult {
  steps: number;
  updatedAt: string;
}

/**
 * Insert or update a user's step total for a given local date.
 * Uses GREATEST so out-of-order or stale POSTs cannot decrease the stored value
 * — HealthKit can deliver late samples.
 *
 * A day whose total CROSSES STREAK_QUALIFYING_STEPS just became a streak day,
 * so the stored streak is refreshed before answering (see stepGoalDaysLanded).
 * Only the crossing does it: the phone posts every few hundred steps all day,
 * and everything after the crossing changes nothing about the streak.
 */
export async function upsertDailySteps(
  userId: string,
  localDate: string,
  steps: number,
  timezoneOffset: number,
): Promise<UpsertDailyStepsResult> {
  // `prev` reads the row as it stood BEFORE this statement (one snapshot for
  // the whole WITH), which is what tells a crossing from a repeat.
  const rows = await db.query<{
    steps: number;
    updated_at: string;
    prev_steps: number | null;
  }>(
    `WITH prev AS (
       SELECT steps FROM daily_steps WHERE user_id = $1 AND local_date = $2::date
     )
     INSERT INTO daily_steps (user_id, local_date, steps, timezone_offset)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (user_id, local_date)
		 DO UPDATE SET
		     steps = GREATEST(daily_steps.steps, EXCLUDED.steps),
		     timezone_offset = EXCLUDED.timezone_offset,
		     updated_at = NOW()
		 RETURNING steps, updated_at::text AS updated_at,
		           (SELECT steps FROM prev) AS prev_steps`,
    [userId, localDate, steps, timezoneOffset],
  );

  const row = rows[0];

  if (crossedGoal(row.prev_steps, row.steps)) {
    await stepGoalDaysLanded(userId, [localDate]);
  }

  // A steps-based weekly challenge can be completed without any workout ever
  // landing, so the workout-sync reward pass would never notice it.
  // Fire-and-forget: a step upsert must not fail because of a challenge.
  evaluateWeeklyChallengeForUser(userId).catch((error: any) => {
    console.error(
      "[WeeklyChallenges] Steps-path evaluation failed:",
      error?.message ?? error,
    );
  });

  return {
    steps: row.steps,
    updatedAt: row.updated_at,
  };
}

function crossedGoal(prev: number | null, now: number): boolean {
  return (
    Number(now) >= STREAK_QUALIFYING_STEPS &&
    (prev === null || Number(prev) < STREAK_QUALIFYING_STEPS)
  );
}

/** Most days one batch may carry: ten years of history. */
export const DAILY_STEPS_BATCH_MAX_DAYS = 3700;

export interface DailyStepsBatchDay {
  localDate: string;
  steps: number;
}

export interface UpsertDailyStepsBatchResult {
  /** Rows written (inserted or raised). */
  upserted: number;
  /** Days this batch turned into 10k-step days. */
  newGoalDays: number;
  /** The stored streak after the batch. */
  streak: number;
}

/**
 * Many days at once — the phone's step HISTORY (first launch of the build
 * where steps count for the streak, and Recalibrate). Same GREATEST rule as
 * the single upsert, ONE statement however many days, then ONE refresh if any
 * day crossed the goal. Posting a decade as single PUTs would be thousands of
 * requests and thousands of streak refreshes.
 *
 * `timezoneOffset` is the device's offset NOW, stamped on every day like the
 * single endpoint does for a backfilled yesterday; `local_date` (computed on
 * the device) is what places the day.
 */
export async function upsertDailyStepsBatch(
  userId: string,
  days: DailyStepsBatchDay[],
  timezoneOffset: number,
): Promise<UpsertDailyStepsBatchResult> {
  if (days.length === 0) {
    return {
      upserted: 0,
      newGoalDays: 0,
      streak: await refreshCurrentStreak(userId),
    };
  }
  // One entry per day: the device can repeat a date across a DST change, and
  // Postgres refuses to touch one row twice in a single ON CONFLICT statement.
  const byDate = new Map<string, number>();
  for (const d of days) {
    byDate.set(d.localDate, Math.max(byDate.get(d.localDate) ?? 0, d.steps));
  }
  const dates = [...byDate.keys()];
  const counts = dates.map((d) => byDate.get(d)!);

  const rows = await db.query<{
    local_date: string;
    steps: number;
    prev_steps: number | null;
  }>(
    `WITH input AS (
       SELECT d::date AS local_date, s::int AS steps
         FROM unnest($2::text[], $3::int[]) AS t(d, s)
     ),
     prev AS (
       SELECT ds.local_date, ds.steps
         FROM daily_steps ds JOIN input i ON i.local_date = ds.local_date
        WHERE ds.user_id = $1
     ),
     up AS (
       INSERT INTO daily_steps (user_id, local_date, steps, timezone_offset)
       SELECT $1, i.local_date, i.steps, $4 FROM input i
       ON CONFLICT (user_id, local_date)
       DO UPDATE SET
           steps = GREATEST(daily_steps.steps, EXCLUDED.steps),
           updated_at = NOW()
       -- Re-sending a day that hasn't grown is a no-op, not a write.
       WHERE EXCLUDED.steps > daily_steps.steps
       RETURNING local_date, steps
     )
     SELECT to_char(up.local_date, 'YYYY-MM-DD') AS local_date, up.steps,
            prev.steps AS prev_steps
       FROM up LEFT JOIN prev ON prev.local_date = up.local_date`,
    [userId, dates, counts, timezoneOffset],
  );

  const crossed = rows
    .filter((r) => crossedGoal(r.prev_steps, r.steps))
    .map((r) => r.local_date);
  const streak =
    crossed.length > 0
      ? await stepGoalDaysLanded(userId, crossed)
      : await refreshCurrentStreak(userId);

  return { upserted: rows.length, newGoalDays: crossed.length, streak };
}

/**
 * One or more days just became 10k-step days for `userId`. Everything a
 * workout upload does for the streak, minus what's about workouts:
 *
 *  - the STORED streak is refreshed (awaited — the client reads /stats the
 *    moment this answers, and without it the hourly decay would zero a
 *    streak that only steps are carrying, and the daily reconcile never
 *    revisits a 0);
 *  - a day older than yesterday can join two old runs into one longer than
 *    any on record, which no current-streak write would notice, so the
 *    longest is re-ratcheted from the eras;
 *  - a token spent on a day the steps now cover is handed back (the classic
 *    case: 10k crossed late at night, synced next morning after the sweep);
 *  - streak medals the new days earned are awarded (silently, like
 *    Recalibrate — the app shows medals as they appear).
 *
 * Returns the refreshed streak. Never throws: a step upload must not fail
 * because a follow-up did.
 */
export async function stepGoalDaysLanded(
  userId: string,
  localDates: string[],
): Promise<number> {
  let streak = 0;
  try {
    streak = await refreshCurrentStreak(userId);
  } catch (err: any) {
    console.error("[Steps] streak refresh failed:", err?.message ?? err);
  }

  try {
    const userToday = await getUserLocalToday(userId);
    const yesterday = new Date(`${userToday}T00:00:00Z`);
    yesterday.setUTCDate(yesterday.getUTCDate() - 1);
    const historical = localDates.some(
      (d) => d < yesterday.toISOString().slice(0, 10),
    );
    if (historical) {
      const { longest } = await computeStreakEras(userId, userToday);
      await ratchetLongestStreak(userId, longest);
    }
  } catch (err: any) {
    console.error("[Steps] longest ratchet failed:", err?.message ?? err);
  }

  refundEarnedCoverage(userId).catch((err: any) =>
    console.error("[Steps] coverage refund failed:", err?.message ?? err),
  );
  void evaluateSocialBadgesForUser(userId);

  return streak;
}

/**
 * Batched per-user, per-day step totals over a date range.
 * Mirrors the shape of getQuantityDateRangeBatch — column aliased as
 * `total_distance` so callers (getUserScores) can treat the value as
 * a generic per-interval quantity.
 *
 * No workout_type filter — daily_steps has no per-activity breakdown.
 */
export async function getStepsDateRangeBatch(
  userIds: string[],
  startDate: string,
  endDate?: string,
): Promise<{ user_id: string; local_date: string; total_distance: number }[]> {
  if (userIds.length === 0) return [];

  const todaysDate = new Date().toISOString().split("T")[0];
  const start = new Date(startDate).toISOString().split("T")[0];
  const end = endDate
    ? new Date(endDate).toISOString().split("T")[0]
    : todaysDate;

  const query = `
		SELECT
			user_id,
			TO_CHAR(local_date, 'YYYY-MM-DD') AS local_date,
			SUM(steps)::int AS total_distance
		FROM daily_steps
		WHERE user_id = ANY($1::text[])
			AND local_date >= $2
			AND local_date <= $3
		GROUP BY user_id, local_date
		ORDER BY user_id, local_date ASC
	`;

  return await db.query(query, [userIds, start, end]);
}
