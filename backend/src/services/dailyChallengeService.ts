import { PostgresService } from "./DbService.js";
import {
  DailyChallenge,
  TodaysChallengeResponse,
  ChallengeCompletionsResponse,
  ChallengeCompletionHistoryItem,
  FriendTodayChallengeResponse,
  NewChallengeCompletion,
  DailyChallengeType,
} from "../types/badge.js";

const db = PostgresService.getInstance();

// ─── Public reads ───────────────────────────────────────────────────

export async function getTodaysChallenge(
  userId: string,
  localDate: string,
): Promise<TodaysChallengeResponse> {
  const goalMiles = await getGoalMiles(userId);

  // A recorded completion pins today's challenge: selection inputs (friend
  // count, feed-feature signals) can flip mid-day, and the challenge the user
  // actually completed must win over a re-pick. Mirrors getTodaysCompletion.
  const completionRow = await getCompletionRow(userId, localDate);
  const completedRow = completionRow
    ? await getChallengeRowByKey(completionRow.challenge_key)
    : null;
  const challengeRow =
    completedRow ?? (await selectChallengeForUser(userId, localDate));
  const challenge = await renderChallenge(userId, challengeRow);

  const progress = completionRow
    ? 1.0
    : await computeProgress(
        userId,
        localDate,
        challengeRow.challenge_key,
        goalMiles,
      );

  // Head-to-Head: attach today's rival + live mileage so the UI can render the duel.
  const opponent =
    challengeRow.challenge_key === "head_to_head"
      ? await buildOpponent(userId, localDate)
      : null;

  const tomorrowLocalDate = addDays(localDate, 1);
  const tomorrowRow = await selectChallengeForUser(userId, tomorrowLocalDate);
  const tomorrowChallenge = await renderChallenge(userId, tomorrowRow);

  return {
    localDate,
    opponent,
    challenge,
    progress,
    completed: !!completionRow,
    completedAt: completionRow?.completed_at ?? null,
    tomorrowChallenge,
    tomorrowLocalDate,
  };
}

export async function getCompletions(
  userId: string,
): Promise<ChallengeCompletionsResponse> {
  const rows = await db.query<any>(
    `SELECT
			ucc.local_date::text AS local_date,
			ucc.challenge_key,
			ucc.completing_workout_id,
			ucc.completed_at,
			dc.title,
			dc.icon
		FROM user_challenge_completions ucc
		JOIN daily_challenges dc ON dc.challenge_key = ucc.challenge_key
		WHERE ucc.user_id = $1
		ORDER BY ucc.local_date DESC`,
    [userId],
  );

  const completions: ChallengeCompletionHistoryItem[] = rows.map((r) => ({
    localDate: r.local_date,
    challengeKey: r.challenge_key,
    title: r.title,
    icon: r.icon,
    completingWorkoutId: r.completing_workout_id,
    completedAt:
      r.completed_at instanceof Date
        ? r.completed_at.toISOString()
        : String(r.completed_at),
  }));

  return {
    totalCompleted: completions.length,
    currentStreak: computeConsecutiveStreak(
      completions.map((c) => c.localDate),
    ),
    completions,
  };
}

export async function getTodaysCompletion(
  userId: string,
  localDate: string,
): Promise<FriendTodayChallengeResponse> {
  const row = await getCompletionRow(userId, localDate);
  // The friend's challenge today (completed → the one they completed; otherwise
  // their selected one). Enriched with title/icon/gradient so the viewer's
  // profile renders it correctly without a hardcoded client catalog.
  let challengeRow: ChallengeRow | null = null;
  try {
    if (row?.challenge_key) {
      challengeRow = await getChallengeRowByKey(row.challenge_key);
    }
    if (!challengeRow) {
      challengeRow = await selectChallengeForUser(userId, localDate);
    }
  } catch {
    challengeRow = null;
  }
  const rendered = challengeRow
    ? await renderChallenge(userId, challengeRow)
    : null;
  return {
    userId,
    localDate,
    completed: !!row,
    challengeKey: row?.challenge_key ?? challengeRow?.challenge_key ?? null,
    challengeTitle: rendered?.title ?? null,
    challengeIcon: rendered?.icon ?? null,
    gradientStart: rendered?.gradientStart ?? null,
    gradientEnd: rendered?.gradientEnd ?? null,
  };
}

// ─── Evaluator ──────────────────────────────────────────────────────

/**
 * For a batch of newly uploaded workouts, evaluate today's challenge for each distinct local_date touched.
 * Returns completions inserted this call (not already-completed days).
 */
export async function evaluateChallengesForBatch(
  userId: string,
  newWorkoutIds: string[],
): Promise<NewChallengeCompletion[]> {
  if (newWorkoutIds.length === 0) return [];

  // Daily challenges are awarded only for *today's* workouts. Historical
  // uploads (e.g. backfilling a week of HealthKit data) must not retroactively
  // unlock past days' challenges.
  const todayLocalDate = await getUserTodayLocalDate(userId);
  if (!todayLocalDate) return [];

  const dateRows = await db.query<{ local_date: string }>(
    `SELECT DISTINCT local_date::text AS local_date
		FROM workouts
		WHERE user_id = $1 AND workout_id = ANY($2::text[]) AND local_date = $3::date AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId, newWorkoutIds, todayLocalDate],
  );

  const completions: NewChallengeCompletion[] = [];
  for (const { local_date } of dateRows) {
    const completion = await evaluateForDay(userId, local_date, newWorkoutIds);
    if (completion) completions.push(completion);
  }
  return completions;
}

/**
 * The user's "today" expressed as a local-date string (YYYY-MM-DD), derived
 * from their most recent workout's timezone offset. Falls back to UTC if the
 * user has no workouts yet (in which case they have nothing to backfill anyway).
 */
async function getUserTodayLocalDate(userId: string): Promise<string | null> {
  const rows = await db.query<{ local_date: string }>(
    `SELECT to_char(
			(now() AT TIME ZONE 'UTC') +
			COALESCE(
				(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
				0
			) * INTERVAL '1 minute',
			'YYYY-MM-DD'
		) AS local_date`,
    [userId],
  );
  return rows[0]?.local_date ?? null;
}

export async function evaluateForDay(
  userId: string,
  localDate: string,
  newWorkoutIds: string[],
): Promise<NewChallengeCompletion | null> {
  const existing = await getCompletionRow(userId, localDate);
  if (existing) return null;

  const challenge = await selectChallengeForUser(userId, localDate);
  const goalMiles = await getGoalMiles(userId);
  const satisfied = await evaluatePredicate(
    userId,
    localDate,
    challenge.challenge_key,
    goalMiles,
  );
  if (!satisfied) return null;

  const completingWorkoutId = await findCompletingWorkout(
    userId,
    localDate,
    newWorkoutIds,
  );

  await db.query(
    `INSERT INTO user_challenge_completions (user_id, local_date, challenge_key, completing_workout_id)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id, local_date) DO NOTHING`,
    [userId, localDate, challenge.challenge_key, completingWorkoutId],
  );

  return {
    localDate,
    challengeKey: challenge.challenge_key,
    challengeTitle: challenge.title,
    completingWorkoutId,
  };
}

// ─── Progress (0..1) for dashboard ring ─────────────────────────────

async function computeProgress(
  userId: string,
  localDate: string,
  challengeKey: string,
  goalMiles: number,
): Promise<number> {
  switch (challengeKey) {
    case "double_down": {
      const d = await dayTotalDistance(userId, localDate);
      return Math.min(d / 2.0, 1.0);
    }
    case "bonus_mile": {
      const d = await dayTotalDistance(userId, localDate);
      return Math.min(d / (goalMiles + 0.5), 1.0);
    }
    case "walk_it_out": {
      const rows = await db.query<{ total: string | null }>(
        `SELECT COALESCE(SUM(distance),0)::text AS total
				FROM workouts WHERE user_id = $1 AND local_date = $2 AND workout_type = 'walking' AND deleted_at IS NULL AND exclusion_reason IS NULL`,
        [userId, localDate],
      );
      const walked = parseFloat(rows[0]?.total ?? "0") || 0;
      const needed = goalMiles * 0.95;
      if (walked >= needed) return 1.0;
      return Math.min(walked / Math.max(goalMiles, 0.01), 0.99);
    }
    case "cross_train": {
      const variant = await crossTrainVariant(userId, localDate);
      const todayMix = await todayRunWalkMix(userId, localDate);
      switch (variant) {
        case "walk_today": {
          const needed = goalMiles * 0.95;
          if (todayMix.walk >= needed) return 1.0;
          return Math.min(todayMix.walk / Math.max(goalMiles, 0.01), 0.99);
        }
        case "run_today": {
          const needed = goalMiles * 0.95;
          if (todayMix.run >= needed) return 1.0;
          return Math.min(todayMix.run / Math.max(goalMiles, 0.01), 0.99);
        }
        case "mixed": {
          const target = 0.5;
          const walkP = Math.min(todayMix.walk / target, 1.0);
          const runP = Math.min(todayMix.run / target, 1.0);
          if (walkP >= 1.0 && runP >= 1.0) return 1.0;
          return Math.min((walkP + runP) / 2.0, 0.99);
        }
      }
    }
    case "ten_k_steps": {
      const rows = await db.query<{ steps: number | null }>(
        `SELECT steps FROM daily_steps WHERE user_id = $1 AND local_date = $2`,
        [userId, localDate],
      );
      const steps = rows[0]?.steps ?? 0;
      return Math.min(steps / 10000.0, 1.0);
    }
    case "speed_round": {
      const rows = await db.query<{
        min_pace: string | null;
        day_total: string | null;
      }>(
        `SELECT
					(SELECT MIN(s.split_pace) FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
					 WHERE w.user_id = $1 AND w.local_date = $2 AND s.split_pace > 0 AND s.split_distance >= 0.95)::text AS min_pace,
					(SELECT COALESCE(SUM(distance),0) FROM workouts WHERE user_id = $1 AND local_date = $2 AND deleted_at IS NULL AND exclusion_reason IS NULL)::text AS day_total`,
        [userId, localDate],
      );
      const dayTotal = parseFloat(rows[0]?.day_total ?? "0") || 0;
      const secPerMi = rows[0]?.min_pace ? parseFloat(rows[0].min_pace) : 0;
      if (dayTotal < 1.0 || secPerMi <= 0) return 0;
      const minPerMi = secPerMi / 60.0;
      if (minPerMi <= 12.0) return 1.0;
      return Math.min(12.0 / minPerMi, 0.99);
    }
    case "early_bird": {
      // Legacy key — historical completions only; same predicate as early_or_late minus night window.
      const rows = await db.query<{
        before_noon: boolean;
        day_total: string | null;
      }>(
        `SELECT
					EXISTS (
						SELECT 1 FROM workouts
						WHERE user_id = $1 AND local_date = $2
						  AND distance >= $3 * 0.95
						  AND EXTRACT(HOUR FROM (device_end_date + timezone_offset * INTERVAL '1 minute')) < 12
					  AND deleted_at IS NULL AND exclusion_reason IS NULL
					) AS before_noon,
					(SELECT COALESCE(SUM(distance),0) FROM workouts WHERE user_id = $1 AND local_date = $2 AND deleted_at IS NULL AND exclusion_reason IS NULL)::text AS day_total`,
        [userId, localDate, goalMiles],
      );
      if (rows[0]?.before_noon) return 1.0;
      const dayTotal = parseFloat(rows[0]?.day_total ?? "0") || 0;
      if (dayTotal >= goalMiles * 0.95) return 0.75;
      return Math.min(dayTotal / Math.max(goalMiles, 0.01), 0.5);
    }
    case "early_or_late": {
      // Completed if a qualifying mile (>= goal * 0.95) finished before 9 AM OR at/after 8 PM local time.
      const rows = await db.query<{
        in_window: boolean;
        day_total: string | null;
      }>(
        `SELECT
					EXISTS (
						SELECT 1 FROM workouts
						WHERE user_id = $1 AND local_date = $2
						  AND distance >= $3 * 0.95
						  AND (
							EXTRACT(HOUR FROM (device_end_date + timezone_offset * INTERVAL '1 minute')) < 9
							OR EXTRACT(HOUR FROM (device_end_date + timezone_offset * INTERVAL '1 minute')) >= 20
						  )
					  AND deleted_at IS NULL AND exclusion_reason IS NULL
					) AS in_window,
					(SELECT COALESCE(SUM(distance),0) FROM workouts WHERE user_id = $1 AND local_date = $2 AND deleted_at IS NULL AND exclusion_reason IS NULL)::text AS day_total`,
        [userId, localDate, goalMiles],
      );
      if (rows[0]?.in_window) return 1.0;
      const dayTotal = parseFloat(rows[0]?.day_total ?? "0") || 0;
      if (dayTotal >= goalMiles * 0.95) return 0.75; // mile done but outside windows
      return Math.min(dayTotal / Math.max(goalMiles, 0.01), 0.5);
    }
    case "beat_your_pace": {
      const rows = await db.query<{
        prior_min: string | null;
        today_min: string | null;
      }>(
        `WITH prior AS (
					SELECT MIN(s.split_pace) AS p
					FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
					WHERE w.user_id = $1 AND w.local_date < $2 AND s.split_pace > 0 AND s.split_distance >= 0.95
				), today AS (
					SELECT MIN(s.split_pace) AS p
					FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
					WHERE w.user_id = $1 AND w.local_date = $2 AND s.split_pace > 0 AND s.split_distance >= 0.95
				)
				SELECT prior.p::text AS prior_min, today.p::text AS today_min FROM prior, today`,
        [userId, localDate],
      );
      const prior = rows[0]?.prior_min ? parseFloat(rows[0].prior_min) : 0;
      const today = rows[0]?.today_min ? parseFloat(rows[0].today_min) : 0;
      if (today <= 0) return 0;
      if (prior <= 0) {
        const d = await dayTotalDistance(userId, localDate);
        return d >= goalMiles * 0.95 ? 1.0 : 0;
      }
      // Target pace = prior + 30s (0.5 min/mi). Check against that target.
      const targetSec = prior + 30;
      if (today <= targetSec) return 1.0;
      return Math.min(targetSec / today, 0.99);
    }
    case "five_k_day":
      return Math.min((await dayTotalDistance(userId, localDate)) / 3.1, 1.0);
    case "ten_k_day":
      return Math.min((await dayTotalDistance(userId, localDate)) / 6.2, 1.0);
    case "two_a_day":
      return Math.min((await workoutCountToday(userId, localDate)) / 2.0, 1.0);
    case "hype_squad":
      return Math.min((await distinctHypesToday(userId, localDate)) / 3.0, 1.0);
    case "share_journey":
      return (await hasPostToday(userId, localDate)) ? 1.0 : 0;
    case "wingman":
      return Math.min((await nudgesToday(userId, localDate)) / 1.0, 1.0);
    case "head_to_head": {
      const opp = await buildOpponent(userId, localDate);
      if (!opp) return 0;
      if (opp.myMiles >= goalMiles * 0.95 && opp.myMiles > opp.miles)
        return 1.0;
      const target = Math.max(opp.miles + 0.01, goalMiles * 0.95);
      return Math.min(opp.myMiles / Math.max(target, 0.01), 0.99);
    }
    default:
      return 0;
  }
}

// ─── Predicate implementations ──────────────────────────────────────

async function evaluatePredicate(
  userId: string,
  localDate: string,
  challengeKey: string,
  goalMiles: number,
): Promise<boolean> {
  switch (challengeKey) {
    case "double_down":
      return (await dayTotalDistance(userId, localDate)) >= 2.0;

    case "bonus_mile":
      return (await dayTotalDistance(userId, localDate)) >= goalMiles + 0.5;

    case "walk_it_out": {
      const rows = await db.query<{ total: string | null }>(
        `SELECT COALESCE(SUM(distance),0)::text AS total
				FROM workouts
				WHERE user_id = $1 AND local_date = $2 AND workout_type = 'walking' AND deleted_at IS NULL AND exclusion_reason IS NULL`,
        [userId, localDate],
      );
      return parseFloat(rows[0]?.total ?? "0") >= goalMiles * 0.95;
    }

    case "cross_train": {
      const variant = await crossTrainVariant(userId, localDate);
      const todayMix = await todayRunWalkMix(userId, localDate);
      switch (variant) {
        case "walk_today":
          return todayMix.walk >= goalMiles * 0.95;
        case "run_today":
          return todayMix.run >= goalMiles * 0.95;
        case "mixed":
          return todayMix.walk >= 0.5 && todayMix.run >= 0.5;
      }
    }

    case "ten_k_steps": {
      const rows = await db.query<{ steps: number | null }>(
        `SELECT steps FROM daily_steps WHERE user_id = $1 AND local_date = $2`,
        [userId, localDate],
      );
      return (rows[0]?.steps ?? 0) >= 10000;
    }

    case "early_bird": {
      const rows = await db.query<{ ok: boolean }>(
        `SELECT EXISTS (
					SELECT 1 FROM workouts
					WHERE user_id = $1 AND local_date = $2
					  AND distance >= $3 * 0.95
					  AND EXTRACT(HOUR FROM (device_end_date + timezone_offset * INTERVAL '1 minute')) < 12
					  AND deleted_at IS NULL AND exclusion_reason IS NULL
				) AS ok`,
        [userId, localDate, goalMiles],
      );
      return !!rows[0]?.ok;
    }

    case "early_or_late": {
      const rows = await db.query<{ ok: boolean }>(
        `SELECT EXISTS (
					SELECT 1 FROM workouts
					WHERE user_id = $1 AND local_date = $2
					  AND distance >= $3 * 0.95
					  AND (
						EXTRACT(HOUR FROM (device_end_date + timezone_offset * INTERVAL '1 minute')) < 9
						OR EXTRACT(HOUR FROM (device_end_date + timezone_offset * INTERVAL '1 minute')) >= 20
					  )
					  AND deleted_at IS NULL AND exclusion_reason IS NULL
				) AS ok`,
        [userId, localDate, goalMiles],
      );
      return !!rows[0]?.ok;
    }

    case "speed_round": {
      const rows = await db.query<{ ok: boolean }>(
        `SELECT (
					EXISTS (
						SELECT 1 FROM workout_splits s
						  JOIN workouts w ON w.workout_id = s.workout_id
						WHERE w.user_id = $1 AND w.local_date = $2
						  AND s.split_pace > 0
						  AND s.split_distance >= 0.95
						  AND s.split_pace / 60.0 <= 12.0
					)
					AND (
						SELECT COALESCE(SUM(distance),0) >= 1.0
						FROM workouts WHERE user_id = $1 AND local_date = $2 AND deleted_at IS NULL AND exclusion_reason IS NULL
					)
				) AS ok`,
        [userId, localDate],
      );
      return !!rows[0]?.ok;
    }

    case "beat_your_pace": {
      const rows = await db.query<{
        prior_min: string | null;
        today_min: string | null;
      }>(
        `WITH prior AS (
					SELECT MIN(s.split_pace) AS p
					FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
					WHERE w.user_id = $1 AND w.local_date < $2 AND s.split_pace > 0 AND s.split_distance >= 0.95
				), today AS (
					SELECT MIN(s.split_pace) AS p
					FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
					WHERE w.user_id = $1 AND w.local_date = $2 AND s.split_pace > 0 AND s.split_distance >= 0.95
				)
				SELECT prior.p::text AS prior_min, today.p::text AS today_min FROM prior, today`,
        [userId, localDate],
      );
      const prior = rows[0]?.prior_min ? parseFloat(rows[0].prior_min) : null;
      const today = rows[0]?.today_min ? parseFloat(rows[0].today_min) : null;
      if (prior === null) {
        return (await dayTotalDistance(userId, localDate)) >= goalMiles * 0.95;
      }
      if (today === null) return false;
      return today <= prior + 30;
    }

    case "five_k_day":
      return (await dayTotalDistance(userId, localDate)) >= 3.1;

    case "ten_k_day":
      return (await dayTotalDistance(userId, localDate)) >= 6.2;

    case "two_a_day":
      return (await workoutCountToday(userId, localDate)) >= 2;

    case "hype_squad":
      return (await distinctHypesToday(userId, localDate)) >= 3;

    case "share_journey":
      return await hasPostToday(userId, localDate);

    case "wingman":
      return (await nudgesToday(userId, localDate)) >= 1;

    case "head_to_head": {
      const opp = await buildOpponent(userId, localDate);
      if (!opp) return false;
      return opp.myMiles >= goalMiles * 0.95 && opp.myMiles > opp.miles;
    }

    default:
      return false;
  }
}

// ─── Helpers ────────────────────────────────────────────────────────

async function dayTotalDistance(
  userId: string,
  localDate: string,
): Promise<number> {
  const rows = await db.query<{ total: string | null }>(
    `SELECT COALESCE(SUM(distance),0)::text AS total FROM workouts WHERE user_id = $1 AND local_date = $2 AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId, localDate],
  );
  return parseFloat(rows[0]?.total ?? "0") || 0;
}

async function workoutCountToday(
  userId: string,
  localDate: string,
): Promise<number> {
  const rows = await db.query<{ c: string }>(
    `SELECT COUNT(*)::text AS c FROM workouts WHERE user_id = $1 AND local_date = $2 AND distance > 0 AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId, localDate],
  );
  return parseInt(rows[0]?.c ?? "0", 10) || 0;
}

/** Distinct friends the user hyped on `localDate` (user's local day). */
async function distinctHypesToday(
  userId: string,
  localDate: string,
): Promise<number> {
  try {
    const rows = await db.query<{ c: string }>(
      `SELECT COUNT(DISTINCT target_id)::text AS c
			FROM hype_log
			WHERE sender_id = $1
				AND (created_at + (COALESCE(
					(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1), 0
				) || ' minutes')::interval)::date = $2::date`,
      [userId, localDate],
    );
    return parseInt(rows[0]?.c ?? "0", 10) || 0;
  } catch {
    return 0;
  }
}

/** Distinct friends the user nudged on `localDate` (friend + competition nudges). */
async function nudgesToday(userId: string, localDate: string): Promise<number> {
  try {
    const tzExpr = `(created_at + (COALESCE(
				(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1), 0
			) || ' minutes')::interval)::date = $2::date`;
    const rows = await db.query<{ c: string }>(
      `SELECT (
				(SELECT COUNT(*) FROM friend_nudge_log WHERE sender_id = $1 AND ${tzExpr})
				+ (SELECT COUNT(*) FROM nudge_log WHERE sender_id = $1 AND ${tzExpr})
			)::text AS c`,
      [userId, localDate],
    );
    return parseInt(rows[0]?.c ?? "0", 10) || 0;
  } catch {
    return 0;
  }
}

/** Whether the user shared a post (story or feed) on `localDate`. */
async function hasPostToday(
  userId: string,
  localDate: string,
): Promise<boolean> {
  try {
    const rows = await db.query<{ ok: boolean }>(
      `SELECT EXISTS (
				SELECT 1 FROM posts WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL
			) AS ok`,
      [userId, localDate],
    );
    return rows[0]?.ok === true;
  } catch {
    return false;
  }
}

async function todayRunWalkMix(
  userId: string,
  localDate: string,
): Promise<{ run: number; walk: number }> {
  const rows = await db.query<{
    workout_type: string | null;
    total: string | null;
  }>(
    `SELECT workout_type, COALESCE(SUM(distance),0)::text AS total
		FROM workouts
		WHERE user_id = $1 AND local_date = $2 AND deleted_at IS NULL AND exclusion_reason IS NULL
		GROUP BY workout_type`,
    [userId, localDate],
  );
  let run = 0;
  let walk = 0;
  for (const r of rows) {
    const v = parseFloat(r.total ?? "0") || 0;
    if (r.workout_type === "running") run += v;
    else if (r.workout_type === "walking") walk += v;
  }
  return { run, walk };
}

type CrossTrainVariant = "walk_today" | "run_today" | "mixed";

/**
 * Pick a cross-train variant based on the user's last-7-days running vs walking mix
 * (excluding today, so the variant is stable for the whole day regardless of new logs).
 *  - Mostly running (<25% walking) → "walk_today" (recovery walk, no run)
 *  - Mostly walking (>75% walking) → "run_today" (push for a run)
 *  - Balanced or no history          → "mixed"   (log both walk + run)
 */
async function crossTrainVariant(
  userId: string,
  localDate: string,
): Promise<CrossTrainVariant> {
  const rows = await db.query<{ run: string | null; walk: string | null }>(
    `SELECT
			COALESCE(SUM(distance) FILTER (WHERE workout_type = 'running'), 0)::text AS run,
			COALESCE(SUM(distance) FILTER (WHERE workout_type = 'walking'), 0)::text AS walk
		FROM workouts
		WHERE user_id = $1
		  AND local_date < $2
		  AND local_date >= ($2::date - INTERVAL '7 days')::date
		  AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId, localDate],
  );
  const run = parseFloat(rows[0]?.run ?? "0") || 0;
  const walk = parseFloat(rows[0]?.walk ?? "0") || 0;
  const total = run + walk;
  if (total < 0.5) return "mixed";
  const walkRatio = walk / total;
  if (walkRatio < 0.25) return "walk_today";
  if (walkRatio > 0.75) return "run_today";
  return "mixed";
}

async function findCompletingWorkout(
  userId: string,
  localDate: string,
  newWorkoutIds: string[],
): Promise<string | null> {
  if (newWorkoutIds.length === 0) return null;
  const rows = await db.query<{ workout_id: string }>(
    `SELECT workout_id FROM workouts
		WHERE user_id = $1 AND local_date = $2 AND workout_id = ANY($3::text[])
		AND deleted_at IS NULL AND exclusion_reason IS NULL
		ORDER BY device_end_date DESC
		LIMIT 1`,
    [userId, localDate, newWorkoutIds],
  );
  return rows[0]?.workout_id ?? null;
}

async function getGoalMiles(userId: string): Promise<number> {
  const rows = await db.query<{ goal_miles: string }>(
    `SELECT goal_miles::text AS goal_miles FROM users WHERE user_id = $1`,
    [userId],
  );
  return parseFloat(rows[0]?.goal_miles ?? "1.0") || 1.0;
}

async function getCompletionRow(
  userId: string,
  localDate: string,
): Promise<{ challenge_key: string; completed_at: string } | null> {
  const rows = await db.query<any>(
    `SELECT challenge_key, completed_at FROM user_challenge_completions WHERE user_id = $1 AND local_date = $2`,
    [userId, localDate],
  );
  const r = rows[0];
  if (!r) return null;
  return {
    challenge_key: r.challenge_key,
    completed_at:
      r.completed_at instanceof Date
        ? r.completed_at.toISOString()
        : String(r.completed_at),
  };
}

/**
 * True if the user has a recorded daily-challenge completion for the given
 * local date. Used to validate `challenge`-context hypes.
 */
export async function hasChallengeCompletion(
  userId: string,
  localDate: string,
): Promise<boolean> {
  const rows = await db.query<{ exists: boolean }>(
    `SELECT EXISTS (
      SELECT 1 FROM user_challenge_completions WHERE user_id = $1 AND local_date = $2::date
    ) AS exists`,
    [userId, localDate],
  );
  return rows[0]?.exists === true;
}

interface ChallengeRow {
  challenge_key: string;
  title: string;
  description_template: string;
  icon: string;
  gradient_start: string;
  gradient_end: string;
  type: "pace" | "distance" | "time" | "activity" | "steps" | "social";
}

/** Social challenges need friends; they're skipped for users with none. */
const SOCIAL_CHALLENGE_KEYS = new Set([
  "hype_squad",
  "share_journey",
  "head_to_head",
  "wingman",
]);

/**
 * Challenges that require the social feed (photo posts). The feed UI is not in
 * the live App Store build yet — and even once it ships, users lingering on
 * older versions won't have it, and there is no app-version signal on API
 * calls. A user provably has the feature once their client has touched a
 * feed-only endpoint: any `posts` row (the feed build auto-posts each
 * completed mile) or UGC-terms acceptance (only reachable from the composer).
 * No signal → the challenge is never offered. Self-heals as users update.
 */
const FEED_CHALLENGE_KEYS = new Set(["share_journey"]);

async function getAcceptedFriendCount(userId: string): Promise<number> {
  try {
    const rows = await db.query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM friendships WHERE user_id = $1 AND status = 'accepted'`,
      [userId],
    );
    return parseInt(rows[0]?.count ?? "0", 10) || 0;
  } catch {
    return 0;
  }
}

/** Whether the user's app build has the social feed (see FEED_CHALLENGE_KEYS). */
async function userHasFeedFeature(userId: string): Promise<boolean> {
  try {
    // Deleted posts still count — even a deleted post proves the build posts.
    const rows = await db.query<{ ok: boolean }>(
      `SELECT (
				EXISTS (SELECT 1 FROM posts WHERE user_id = $1)
				OR EXISTS (SELECT 1 FROM users WHERE user_id = $1 AND terms_accepted_at IS NOT NULL)
			) AS ok`,
      [userId],
    );
    return rows[0]?.ok === true;
  } catch {
    return false;
  }
}

/**
 * Per-user daily challenge selection. The base pick is deterministic by date
 * (so friends on the same day tend to share a challenge), but a challenge the
 * user can't actually complete is skipped — we deterministically advance to
 * the next eligible challenge in the rotation so they always get something
 * actionable:
 *  - social challenges are skipped for users with no accepted friends
 *  - feed challenges are skipped for users whose app build lacks the feed
 */
async function selectChallengeForUser(
  userId: string,
  localDate: string,
): Promise<ChallengeRow> {
  const rows = await db.query<ChallengeRow>(
    `SELECT challenge_key, title, description_template, icon, gradient_start, gradient_end, type
		FROM daily_challenges
		WHERE active = TRUE
		ORDER BY rotation_index ASC`,
  );
  if (rows.length === 0)
    throw new Error("No active daily challenges configured");

  const baseIdx = dayOfYear(localDate) % rows.length;

  // Eligibility signals resolved lazily and at most once per selection —
  // the common (non-gated) base pick costs no extra queries.
  let friendCount: number | null = null;
  let hasFeed: boolean | null = null;
  const isEligible = async (row: ChallengeRow): Promise<boolean> => {
    if (SOCIAL_CHALLENGE_KEYS.has(row.challenge_key)) {
      friendCount ??= await getAcceptedFriendCount(userId);
      if (friendCount === 0) return false;
    }
    if (FEED_CHALLENGE_KEYS.has(row.challenge_key)) {
      hasFeed ??= await userHasFeedFeature(userId);
      if (!hasFeed) return false;
    }
    return true;
  };

  for (let i = 0; i < rows.length; i++) {
    const candidate = rows[(baseIdx + i) % rows.length];
    if (await isEligible(candidate)) return candidate;
  }
  return rows[baseIdx]; // nothing eligible (shouldn't happen) — fall back to the base pick
}

/**
 * Deterministic "rival of the day" for Head-to-Head: a stable pick from the
 * user's accepted friends seeded by user + date. Returns null if no friends.
 */
async function selectRival(
  userId: string,
  localDate: string,
): Promise<string | null> {
  const rows = await db.query<{ friend_id: string }>(
    `SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted' ORDER BY friend_id ASC`,
    [userId],
  );
  if (rows.length === 0) return null;
  // Simple stable hash of (userId + localDate).
  const seedStr = `${userId}|${localDate}`;
  let hash = 0;
  for (let i = 0; i < seedStr.length; i++) {
    hash = (hash * 31 + seedStr.charCodeAt(i)) >>> 0;
  }
  return rows[hash % rows.length].friend_id;
}

async function getChallengeRowByKey(key: string): Promise<ChallengeRow | null> {
  const rows = await db.query<ChallengeRow>(
    `SELECT challenge_key, title, description_template, icon, gradient_start, gradient_end, type
		FROM daily_challenges WHERE challenge_key = $1`,
    [key],
  );
  return rows[0] ?? null;
}

/** Build the Head-to-Head opponent payload (rival + both of today's mileages). */
async function buildOpponent(
  userId: string,
  localDate: string,
): Promise<import("../types/badge.js").ChallengeOpponent | null> {
  const rivalId = await selectRival(userId, localDate);
  if (!rivalId) return null;
  const [info] = await db.query<{
    username: string | null;
    profile_image_url: string | null;
  }>(`SELECT username, profile_image_url FROM users WHERE user_id = $1`, [
    rivalId,
  ]);
  const rivalMiles = await dayTotalDistance(rivalId, localDate);
  const myMiles = await dayTotalDistance(userId, localDate);
  return {
    userId: rivalId,
    username: info?.username ?? null,
    profileImageUrl: info?.profile_image_url ?? null,
    miles: Math.round(rivalMiles * 100) / 100,
    myMiles: Math.round(myMiles * 100) / 100,
  };
}

function dayOfYear(ymd: string): number {
  const [y, m, d] = ymd.split("-").map((n) => parseInt(n, 10));
  const start = Date.UTC(y, 0, 1);
  const curr = Date.UTC(y, m - 1, d);
  return Math.floor((curr - start) / 86400000) + 1;
}

function addDays(ymd: string, n: number): string {
  const [y, m, d] = ymd.split("-").map((v) => parseInt(v, 10));
  const ms = Date.UTC(y, m - 1, d) + n * 86400000;
  const date = new Date(ms);
  const yy = date.getUTCFullYear();
  const mm = String(date.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(date.getUTCDate()).padStart(2, "0");
  return `${yy}-${mm}-${dd}`;
}

/**
 * Resolve a `ChallengeRow` into the public `DailyChallenge` shape, applying any per-user
 * personalization (pace targets, dynamic variants).
 */
async function renderChallenge(
  userId: string,
  row: ChallengeRow,
): Promise<DailyChallenge> {
  // Dynamic cross-train variant — title / description / icon all flex with the user's recent mix.
  if (row.challenge_key === "cross_train") {
    // Use today's date in user's local time to pick the variant.
    const localDate = await resolveUserLocalDate(userId);
    const variant = await crossTrainVariant(userId, localDate);
    return shapeCrossTrain(row, variant);
  }

  // Head-to-Head: personalize the description with today's rival's name.
  if (row.challenge_key === "head_to_head") {
    const localDate = await resolveUserLocalDate(userId);
    const opp = await buildOpponent(userId, localDate);
    const name = opp?.username ?? "a friend";
    return {
      key: row.challenge_key,
      title: row.title,
      description: opp
        ? `Out-run ${name} today — log more miles than them!`
        : "Out-run a friend today — log more miles than them!",
      icon: row.icon,
      gradientStart: row.gradient_start,
      gradientEnd: row.gradient_end,
      type: row.type,
    };
  }

  const description = await renderDescription(userId, row);
  return {
    key: row.challenge_key,
    title: row.title,
    description,
    icon: row.icon,
    gradientStart: row.gradient_start,
    gradientEnd: row.gradient_end,
    type: row.type,
  };
}

function shapeCrossTrain(
  row: ChallengeRow,
  variant: CrossTrainVariant,
): DailyChallenge {
  switch (variant) {
    case "walk_today":
      return {
        key: row.challenge_key,
        title: "Recovery Walk",
        description:
          "You've been logging miles — take a walking-only mile today to recover.",
        icon: "figure.walk.motion",
        gradientStart: "#34C759",
        gradientEnd: "#30D158",
        type: row.type,
      };
    case "run_today":
      return {
        key: row.challenge_key,
        title: "Lace ’Em Up",
        description:
          "It's been mostly walks lately — log your mile as a run today.",
        icon: "figure.run",
        gradientStart: "#FF9500",
        gradientEnd: "#FF3B30",
        type: row.type,
      };
    case "mixed":
      return {
        key: row.challenge_key,
        title: "Mix It Up",
        description: "Log both a walk and a run today (at least 0.5 mi each).",
        icon: "figure.mixed.cardio",
        gradientStart: "#34C759",
        gradientEnd: "#5AC8FA",
        type: row.type,
      };
  }
}

async function resolveUserLocalDate(userId: string): Promise<string> {
  const rows = await db.query<{ local_date: string }>(
    `SELECT (NOW() + (
			COALESCE(
				(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
				0
			) || ' minutes'
		)::interval)::date::text AS local_date`,
    [userId],
  );
  return rows[0]?.local_date ?? new Date().toISOString().slice(0, 10);
}

async function renderDescription(
  userId: string,
  challenge: ChallengeRow,
): Promise<string> {
  if (!challenge.description_template.includes("{avg_pace}")) {
    return challenge.description_template;
  }
  // Personalize for beat_your_pace (and any future pace challenges).
  const rows = await db.query<{ min_pace: string | null }>(
    `SELECT MIN(s.split_pace)::text AS min_pace
		FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
		WHERE w.user_id = $1 AND s.split_pace > 0 AND s.split_distance >= 0.95`,
    [userId],
  );
  const secPerMile = rows[0]?.min_pace ? parseFloat(rows[0].min_pace) : 0;
  if (secPerMile <= 0) return "Set a new personal best pace today";
  const targetMinPerMi = secPerMile / 60.0 + 0.5;
  return challenge.description_template.replace(
    "{avg_pace}",
    formatPace(targetMinPerMi),
  );
}

function formatPace(minutesPerMile: number): string {
  const m = Math.floor(minutesPerMile);
  const s = Math.round((minutesPerMile - m) * 60);
  const ss = s < 10 ? `0${s}` : `${s}`;
  return `${m}:${ss}`;
}

// ─── Startup seed ───────────────────────────────────────────────────

/**
 * New v2 daily challenges (harder distance goals + social challenges). Idempotent:
 * widens the `type` CHECK to allow `'social'`, then inserts any missing catalog
 * rows. Runs at startup so a deploy needs no manual SQL. `cross_train` already
 * ships in the base catalog, so it's intentionally not repeated here.
 *
 * Rotation indices 7–12 extend the existing 0–6 active rotation; legacy retired
 * challenges live at 100+, so there's no collision with the UNIQUE(rotation_index).
 */
const EXTRA_CHALLENGES: Array<{
  key: string;
  title: string;
  description: string;
  icon: string;
  gradientStart: string;
  gradientEnd: string;
  type: DailyChallengeType;
  rotationIndex: number;
}> = [
  {
    key: "five_k_day",
    title: "5K Day",
    description: "Go the distance — cover 3.1 miles (a full 5K) today",
    icon: "figure.run",
    gradientStart: "#FF9500",
    gradientEnd: "#FF3B30",
    type: "distance",
    rotationIndex: 7,
  },
  {
    key: "ten_k_day",
    title: "10K Day",
    description: "Big effort — cover 6.2 miles (a full 10K) today",
    icon: "figure.run.circle.fill",
    gradientStart: "#AF52DE",
    gradientEnd: "#FF2D55",
    type: "distance",
    rotationIndex: 8,
  },
  {
    key: "two_a_day",
    title: "Two-a-Day",
    description: "Log two separate workouts today",
    icon: "arrow.triangle.2.circlepath",
    gradientStart: "#5AC8FA",
    gradientEnd: "#34C759",
    type: "activity",
    rotationIndex: 9,
  },
  {
    key: "hype_squad",
    title: "Hype Squad",
    description: "Cheer on 3 different friends today",
    icon: "hands.clap.fill",
    gradientStart: "#FF2D55",
    gradientEnd: "#FF9500",
    type: "social",
    rotationIndex: 10,
  },
  {
    key: "share_journey",
    title: "Share the Journey",
    description: "Post a photo to the feed today",
    icon: "camera.fill",
    gradientStart: "#007AFF",
    gradientEnd: "#AF52DE",
    type: "social",
    rotationIndex: 11,
  },
  {
    key: "head_to_head",
    title: "Head-to-Head",
    description: "Out-run a friend today — log more miles than them!",
    icon: "flag.2.crossed.fill",
    gradientStart: "#FF3B30",
    gradientEnd: "#5856D6",
    type: "social",
    rotationIndex: 12,
  },
  {
    key: "wingman",
    title: "Wingman",
    description: "Nudge a friend to get their mile in today",
    icon: "hand.wave.fill",
    gradientStart: "#FF9500",
    gradientEnd: "#FF2D55",
    type: "social",
    rotationIndex: 13,
  },
];

export async function seedExtraChallenges(): Promise<void> {
  try {
    // Widen the type CHECK so `'social'` rows are allowed. Idempotent; the table
    // is tiny so the brief lock is negligible. Self-contained so the runtime
    // doesn't depend on the Drizzle migration having been applied yet.
    await db.query(
      `ALTER TABLE daily_challenges DROP CONSTRAINT IF EXISTS daily_challenges_type_check`,
    );
    await db.query(
      `ALTER TABLE daily_challenges ADD CONSTRAINT daily_challenges_type_check
			 CHECK (type = ANY (ARRAY['pace'::text, 'distance'::text, 'time'::text, 'activity'::text, 'steps'::text, 'social'::text]))`,
    );

    const queries = EXTRA_CHALLENGES.map((c) => ({
      query: `INSERT INTO daily_challenges
					(challenge_key, title, description_template, icon, gradient_start, gradient_end, type, active, rotation_index)
				VALUES ($1, $2, $3, $4, $5, $6, $7, true, $8)
				ON CONFLICT (challenge_key) DO NOTHING`,
      params: [
        c.key,
        c.title,
        c.description,
        c.icon,
        c.gradientStart,
        c.gradientEnd,
        c.type,
        c.rotationIndex,
      ],
    }));
    await db.transaction(queries);
    console.log(
      `[challenges] Seeded ${EXTRA_CHALLENGES.length} v2 daily challenges (idempotent).`,
    );
  } catch (e: any) {
    console.error("[challenges] seedExtraChallenges failed:", e?.message ?? e);
  }
}

function computeConsecutiveStreak(datesDesc: string[]): number {
  if (datesDesc.length === 0) return 0;
  let streak = 1;
  for (let i = 1; i < datesDesc.length; i++) {
    const [y1, m1, d1] = datesDesc[i].split("-").map((n) => parseInt(n, 10));
    const [y2, m2, d2] = datesDesc[i - 1]
      .split("-")
      .map((n) => parseInt(n, 10));
    const earlier = Date.UTC(y1, m1 - 1, d1);
    const later = Date.UTC(y2, m2 - 1, d2);
    if (later - earlier !== 86400000) break;
    streak++;
  }
  return streak;
}
