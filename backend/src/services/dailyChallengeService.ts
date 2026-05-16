import { PostgresService } from "./DbService.js";
import {
  DailyChallenge,
  TodaysChallengeResponse,
  ChallengeCompletionsResponse,
  ChallengeCompletionHistoryItem,
  FriendTodayChallengeResponse,
  NewChallengeCompletion,
} from "../types/badge.js";

const db = PostgresService.getInstance();

// ─── Public reads ───────────────────────────────────────────────────

export async function getTodaysChallenge(
  userId: string,
  localDate: string,
): Promise<TodaysChallengeResponse> {
  const goalMiles = await getGoalMiles(userId);
  const challengeRow = await selectChallengeForDate(localDate);
  const challenge = await renderChallenge(userId, challengeRow);

  const completionRow = await getCompletionRow(userId, localDate);
  const progress = completionRow
    ? 1.0
    : await computeProgress(
        userId,
        localDate,
        challengeRow.challenge_key,
        goalMiles,
      );

  const tomorrowLocalDate = addDays(localDate, 1);
  const tomorrowRow = await selectChallengeForDate(tomorrowLocalDate);
  const tomorrowChallenge = await renderChallenge(userId, tomorrowRow);

  return {
    localDate,
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
  return {
    userId,
    localDate,
    completed: !!row,
    challengeKey: row?.challenge_key ?? null,
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

  const dateRows = await db.query<{ local_date: string }>(
    `SELECT DISTINCT local_date::text AS local_date
		FROM workouts
		WHERE user_id = $1 AND workout_id = ANY($2::text[])`,
    [userId, newWorkoutIds],
  );

  const completions: NewChallengeCompletion[] = [];
  for (const { local_date } of dateRows) {
    const completion = await evaluateForDay(userId, local_date, newWorkoutIds);
    if (completion) completions.push(completion);
  }
  return completions;
}

export async function evaluateForDay(
  userId: string,
  localDate: string,
  newWorkoutIds: string[],
): Promise<NewChallengeCompletion | null> {
  const existing = await getCompletionRow(userId, localDate);
  if (existing) return null;

  const challenge = await selectChallengeForDate(localDate);
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
				FROM workouts WHERE user_id = $1 AND local_date = $2 AND workout_type = 'walking'`,
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
					(SELECT COALESCE(SUM(distance),0) FROM workouts WHERE user_id = $1 AND local_date = $2)::text AS day_total`,
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
					) AS before_noon,
					(SELECT COALESCE(SUM(distance),0) FROM workouts WHERE user_id = $1 AND local_date = $2)::text AS day_total`,
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
					) AS in_window,
					(SELECT COALESCE(SUM(distance),0) FROM workouts WHERE user_id = $1 AND local_date = $2)::text AS day_total`,
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
				WHERE user_id = $1 AND local_date = $2 AND workout_type = 'walking'`,
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
						FROM workouts WHERE user_id = $1 AND local_date = $2
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
    `SELECT COALESCE(SUM(distance),0)::text AS total FROM workouts WHERE user_id = $1 AND local_date = $2`,
    [userId, localDate],
  );
  return parseFloat(rows[0]?.total ?? "0") || 0;
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
		WHERE user_id = $1 AND local_date = $2
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
		  AND local_date >= ($2::date - INTERVAL '7 days')::date`,
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

interface ChallengeRow {
  challenge_key: string;
  title: string;
  description_template: string;
  icon: string;
  gradient_start: string;
  gradient_end: string;
  type: "pace" | "distance" | "time" | "activity" | "steps";
}

async function selectChallengeForDate(
  localDate: string,
): Promise<ChallengeRow> {
  // Rotation is stable as long as active rows keep their rotation_index; we order by rotation_index
  // and pick via (day_of_year % count).
  const rows = await db.query<ChallengeRow>(
    `SELECT challenge_key, title, description_template, icon, gradient_start, gradient_end, type
		FROM daily_challenges
		WHERE active = TRUE
		ORDER BY rotation_index ASC`,
  );
  if (rows.length === 0)
    throw new Error("No active daily challenges configured");
  const doy = dayOfYear(localDate);
  return rows[doy % rows.length];
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
