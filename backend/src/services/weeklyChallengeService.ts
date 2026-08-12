import { PostgresService } from "./DbService.js";
import { countedWorkoutSql, realMileSplitSql } from "./mileTime.js";
import { DAILY_GOAL_TOLERANCE } from "./workoutService.js";
import { weekOfEpoch } from "./challengeRotation.js";
import { getBlockedIds } from "./moderationService.js";
import { sendPush } from "./pushNotificationService.js";
import { shouldSendNotification } from "./notificationSettingsService.js";
import { CLIENT_FEATURES, userSupports } from "./clientFeatures.js";

const db = PostgresService.getInstance();

/**
 * Weekly challenges: one global theme per ISO week, with a per-user target.
 *
 * The theme is a pure function of the Monday date, so everyone eligible sees
 * the same challenge in the same week — that shared-event feeling is the whole
 * point of the friends leaderboard. The NUMBER is personal: a flat global
 * target is trivial for someone running 40 miles a week and impossible for
 * someone doing their first mile, so it scales from the user's own trailing
 * four weeks.
 *
 * The target is frozen at first serve. See `serveWeek`.
 */

/** Metrics a challenge can be measured in. Mirrored by the CHECK in `seed`. */
export type WeeklyMetric =
  | "total_distance"
  | "mile_days"
  | "active_days"
  | "longest_single_workout"
  | "total_steps"
  | "early_workouts"
  | "late_workouts"
  | "weekend_distance"
  | "total_minutes"
  | "fast_mile_splits"
  | "workout_count"
  | "consecutive_active_days";

export interface WeeklyChallengeRow {
  challenge_key: string;
  title: string;
  description_template: string;
  icon: string;
  gradient_start: string;
  gradient_end: string;
  metric: WeeklyMetric;
  unit: string;
  base_target: number;
  scale_multiplier: number;
  scale_min_multiplier: number;
  scale_max_multiplier: number;
  target_ceiling: number;
  target_step: number;
  rotation_index: number;
}

export interface WeekWindow {
  weekStart: string;
  weekEnd: string;
  /** The user's own today. Progress never counts past it. */
  localToday: string;
}

/**
 * A user's local week, Monday-start.
 *
 * `date_trunc('week')` is ISO Monday-start in Postgres, and the timezone
 * COALESCE is the same one `weeklyRecapCron` uses — the stored preference
 * first, then the timezone of their most recent workout. Every read and write
 * in this module goes through here so the boundary can't drift between
 * surfaces.
 */
export async function weekWindowForUser(userId: string): Promise<WeekWindow> {
  const rows = await db.query<{
    week_start: string;
    week_end: string;
    local_today: string;
  }>(
    `WITH tz AS (
			SELECT COALESCE(
				(SELECT ns.timezone_offset_minutes FROM notification_settings ns WHERE ns.user_id = $1),
				(SELECT w.timezone_offset FROM workouts w WHERE w.user_id = $1 ORDER BY w.device_end_date DESC LIMIT 1),
				0
			) AS offset_minutes
		)
		SELECT
			date_trunc('week', NOW() + (tz.offset_minutes || ' minutes')::interval)::date::text AS week_start,
			(date_trunc('week', NOW() + (tz.offset_minutes || ' minutes')::interval)::date + 6)::text AS week_end,
			(NOW() + (tz.offset_minutes || ' minutes')::interval)::date::text AS local_today
		FROM tz`,
    [userId],
  );

  const row = rows[0];
  // Only reachable if the user row vanished mid-request; fall back to UTC.
  if (!row) {
    const now = new Date();
    const day = (now.getUTCDay() + 6) % 7; // Monday = 0
    const monday = new Date(now);
    monday.setUTCDate(now.getUTCDate() - day);
    const sunday = new Date(monday);
    sunday.setUTCDate(monday.getUTCDate() + 6);
    const ymd = (d: Date) => d.toISOString().slice(0, 10);
    return {
      weekStart: ymd(monday),
      weekEnd: ymd(sunday),
      localToday: ymd(now),
    };
  }

  return {
    weekStart: row.week_start,
    weekEnd: row.week_end,
    localToday: row.local_today,
  };
}

/** Active catalog, in rotation order. */
export async function getCatalog(): Promise<WeeklyChallengeRow[]> {
  return db.query<WeeklyChallengeRow>(
    `SELECT challenge_key, title, description_template, icon,
			gradient_start, gradient_end, metric, unit,
			base_target, scale_multiplier, scale_min_multiplier,
			scale_max_multiplier, target_ceiling, target_step, rotation_index
		FROM weekly_challenges
		WHERE active = TRUE
		ORDER BY rotation_index ASC`,
  );
}

export async function getChallengeByKey(
  key: string,
): Promise<WeeklyChallengeRow | null> {
  const rows = await db.query<WeeklyChallengeRow>(
    `SELECT challenge_key, title, description_template, icon,
			gradient_start, gradient_end, metric, unit,
			base_target, scale_multiplier, scale_min_multiplier,
			scale_max_multiplier, target_ceiling, target_step, rotation_index
		FROM weekly_challenges WHERE challenge_key = $1`,
    [key],
  );
  return rows[0] ?? null;
}

/**
 * The week's challenge, globally.
 *
 * Seeded by the week index so every user lands on the same row. The only
 * per-user gate is a steps challenge for someone whose app has never synced
 * steps — that week would be literally unwinnable for them, so the walk
 * advances. Deterministic either way.
 */
export async function selectChallengeForWeek(
  userId: string,
  weekStart: string,
  catalog?: WeeklyChallengeRow[],
): Promise<WeeklyChallengeRow | null> {
  const rows = catalog ?? (await getCatalog());
  if (rows.length === 0) return null;

  // Straight modulo — no eligibility walk. Advancing to the next entry when a
  // challenge doesn't fit would land on the row the FOLLOWING week is about to
  // serve, and the user would get the same challenge two weeks running.
  const pick =
    rows[((weekOfEpoch(weekStart) % rows.length) + rows.length) % rows.length];

  // A steps week is unwinnable for someone whose app has never synced steps, so
  // they get a fixed off-rotation substitute instead — the same shape as the
  // daily catalog's `add_friend`, and collision-free precisely because it sits
  // outside the rotation.
  if (pick.metric === "total_steps") {
    const synced = await db.query<{ ok: boolean }>(
      `SELECT EXISTS (
				SELECT 1 FROM daily_steps
				WHERE user_id = $1 AND local_date >= ($2::date - 28)
			) AS ok`,
      [userId, weekStart],
    );
    if (synced[0]?.ok !== true) {
      return (await getChallengeByKey(STEPS_SUBSTITUTE_KEY)) ?? pick;
    }
  }

  return pick;
}

/**
 * Shown in place of a steps week to users with no step data. Lives outside the
 * rotation (`active = false`) so it can never be picked on its own and can
 * never collide with the following week's entry.
 */
export const STEPS_SUBSTITUTE_KEY = "move_more";

// MARK: - Target scaling

function roundToStep(value: number, step: number): number {
  if (!(step > 0)) return Math.round(value);
  return Math.round(value / step) * step;
}

/**
 * Scale a challenge's target to one user.
 *
 * `baseline` is their average of the SAME metric over the four complete weeks
 * before this one — the current week is excluded so today's running can't move
 * today's target.
 *
 * The result is roughly `baseline * scale_multiplier` (a ~10% stretch), bounded
 * three ways:
 *   - `base_target` pulls a light week UP, so the challenge stays worth doing;
 *   - `scale_max_multiplier` caps how far above their own average anyone is
 *     pushed, which is what stops `base_target` from handing a beginner a
 *     number they have no chance at;
 *   - `target_ceiling` is the absolute sanity cap.
 *
 * A worked example of why the bounds are multiples of the BASELINE rather than
 * of `base_target`: with base 10 and a 2.5x cap anchored to base, everyone
 * would top out at 25, so someone averaging 40 miles a week would be set a
 * target comfortably below what they already do.
 */
export function resolveTarget(
  row: WeeklyChallengeRow,
  baseline: number | null,
): { target: number; baseline: number | null } {
  if (baseline === null || !(baseline > 0)) {
    return { target: roundToStep(row.base_target, row.target_step), baseline };
  }

  const raw = baseline * row.scale_multiplier;

  // The clamps are multiples of the USER'S OWN baseline, not of base_target.
  // Anchoring them to base_target caps everyone at the same number, which
  // inverts the whole point: with a base of 10 and a 2.5x cap, someone
  // averaging 40 miles a week would be set a target of 25 — comfortably less
  // than they already do. `base_target` is only ever a FLOOR.
  const lower = Math.max(row.base_target, baseline * row.scale_min_multiplier);
  const upper = Math.min(
    baseline * row.scale_max_multiplier,
    row.target_ceiling,
  );

  // A very strong user can push `lower` above `upper` once target_ceiling bites;
  // the absolute ceiling wins, since it's the one that keeps the number sane.
  const target = roundToStep(
    Math.min(Math.max(raw, Math.min(lower, upper)), upper),
    row.target_step,
  );

  return { target: Math.min(target, row.target_ceiling), baseline };
}

/**
 * Average of `metric` over the four complete weeks before `weekStart`.
 * Null when the user has under two weeks of history — too little to scale
 * from, so they get `base_target`.
 */
export async function computeBaseline(
  userId: string,
  metric: WeeklyMetric,
  weekStart: string,
): Promise<number | null> {
  const values = await Promise.all(
    [4, 3, 2, 1].map((weeksBack) => {
      const start = addDays(weekStart, -7 * weeksBack);
      return measure(userId, metric, start, addDays(start, 6));
    }),
  );

  // Average over the weeks they actually did something. Including blank weeks
  // would drag the target down for anyone who took a holiday, which is the
  // opposite of what a rest week should do to next week's challenge.
  const active = values.filter((v) => v > 0);
  if (active.length < 2) return null;
  return active.reduce((sum, v) => sum + v, 0) / active.length;
}

/** Plain date math on a "YYYY-MM-DD" string, in UTC so no timezone can shift it. */
function addDays(ymd: string, days: number): string {
  const [y, m, d] = ymd.split("-").map((n) => parseInt(n, 10));
  const date = new Date(Date.UTC(y, m - 1, d));
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

// MARK: - Progress

/**
 * A user's value for one metric over an inclusive local-date range.
 *
 * Every workout-derived arm carries `countedWorkoutSql` — a Strava duplicate of
 * a run HealthKit already recorded, or a drive classified `vehicle_speed`,
 * must not win anybody a challenge when it doesn't count toward their miles.
 * The split-based arm needs it on the WORKOUT specifically: reaching workouts
 * through `workout_splits` and forgetting it is how excluded rides came to own
 * the fastest split.
 */
export async function measure(
  userId: string,
  metric: WeeklyMetric,
  fromDate: string,
  toDate: string,
): Promise<number> {
  const params = [userId, fromDate, toDate];

  switch (metric) {
    case "total_distance":
      return scalar(
        `SELECT COALESCE(SUM(w.distance), 0) AS v
			FROM workouts w
			WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
				AND ${countedWorkoutSql("w")}`,
        params,
      );

    case "weekend_distance":
      return scalar(
        `SELECT COALESCE(SUM(w.distance), 0) AS v
			FROM workouts w
			WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
				AND EXTRACT(DOW FROM w.local_date) IN (0, 6)
				AND ${countedWorkoutSql("w")}`,
        params,
      );

    case "longest_single_workout":
      return scalar(
        `SELECT COALESCE(MAX(w.distance), 0) AS v
			FROM workouts w
			WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
				AND ${countedWorkoutSql("w")}`,
        params,
      );

    case "total_minutes":
      return scalar(
        `SELECT COALESCE(SUM(w.total_duration), 0) / 60.0 AS v
			FROM workouts w
			WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
				AND ${countedWorkoutSql("w")}`,
        params,
      );

    case "workout_count":
      return scalar(
        `SELECT COUNT(*) AS v
			FROM workouts w
			WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
				AND w.distance >= 0.25
				AND ${countedWorkoutSql("w")}`,
        params,
      );

    case "active_days":
      return scalar(
        `SELECT COUNT(DISTINCT w.local_date) AS v
			FROM workouts w
			WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
				AND w.distance >= 0.25
				AND ${countedWorkoutSql("w")}`,
        params,
      );

    // A "hit your goal" day is the 0.95 tolerance, never a raw >= goal: the
    // rest of the app counts a 0.96-mile day against a 1-mile goal as done, and
    // a stricter test here would call a day the dashboard shows as complete a
    // miss. `goal_miles` is clamped because the helper is vacuously true at 0.
    case "mile_days":
      return scalar(
        `WITH goal AS (
				SELECT GREATEST(COALESCE(u.goal_miles, 1), 0.1) AS g
				FROM users u WHERE u.user_id = $1
			)
			SELECT COUNT(*) AS v FROM (
				SELECT w.local_date
				FROM workouts w, goal
				WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
					AND ${countedWorkoutSql("w")}
				GROUP BY w.local_date, goal.g
				HAVING SUM(w.distance) >= goal.g::double precision * ${DAILY_GOAL_TOLERANCE}
			) days`,
        params,
      );

    case "total_steps":
      return scalar(
        `SELECT COALESCE(SUM(ds.steps), 0) AS v
			FROM daily_steps ds
			WHERE ds.user_id = $1 AND ds.local_date BETWEEN $2::date AND $3::date`,
        params,
      );

    // Local START hour, derived by walking back from the end timestamp — a run
    // that began at 6am and took an hour is an early one.
    case "early_workouts":
    case "late_workouts": {
      const test = metric === "early_workouts" ? "< 8" : ">= 20";
      return scalar(
        `SELECT COUNT(*) AS v
			FROM workouts w
			WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
				AND w.distance >= 0.25
				AND ${countedWorkoutSql("w")}
				AND EXTRACT(HOUR FROM (
					w.device_end_date
					- (COALESCE(w.total_duration, 0) || ' seconds')::interval
					+ (w.timezone_offset || ' minutes')::interval
				)) ${test}`,
        params,
      );
    }

    case "fast_mile_splits":
      return scalar(
        `SELECT COUNT(*) AS v
			FROM workout_splits ws
			JOIN workouts w ON w.workout_id = ws.workout_id
			WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
				AND ${countedWorkoutSql("w")}
				AND ${realMileSplitSql("ws.split_pace")}
				AND ws.split_pace <= 600`,
        params,
      );

    // Gaps and islands. The island key must move OPPOSITE to the row
    // numbering: an ASC walk pairs with (d - rn). The reverse pairing looks
    // fine and silently returns 1 for every real streak.
    case "consecutive_active_days":
      return scalar(
        `WITH days AS (
				SELECT DISTINCT w.local_date AS d
				FROM workouts w
				WHERE w.user_id = $1 AND w.local_date BETWEEN $2::date AND $3::date
					AND w.distance >= 0.25
					AND ${countedWorkoutSql("w")}
			),
			islands AS (
				SELECT d, d - (ROW_NUMBER() OVER (ORDER BY d ASC))::int AS island
				FROM days
			)
			SELECT COALESCE(MAX(run), 0) AS v
			FROM (SELECT COUNT(*) AS run FROM islands GROUP BY island) runs`,
        params,
      );
  }
}

async function scalar(sql: string, params: unknown[]): Promise<number> {
  const rows = await db.query<{ v: string | number | null }>(sql, params);
  const value = rows[0]?.v;
  if (value === null || value === undefined) return 0;
  return typeof value === "number" ? value : parseFloat(value) || 0;
}

// MARK: - Serving (and freezing) a week

export interface ServedWeek {
  challenge: WeeklyChallengeRow;
  target: number;
  baseline: number | null;
  weekStart: string;
}

/**
 * The user's challenge and target for a week, stamping both on first serve.
 *
 * The stamp is the point. Selection and scaling are otherwise pure functions of
 * the date and the user's history, re-derived on every read — which means the
 * target moves as they run (their trailing average is an input), and changing
 * the scaling formula silently rewrites what past weeks "asked for". Freezing
 * on first serve makes the week a fact instead of a recomputation, exactly as
 * `user_daily_challenges` does for the day's pick.
 *
 * `ON CONFLICT DO NOTHING` plus a re-read means concurrent callers converge on
 * whichever landed first rather than one overwriting the other.
 */
export async function serveWeek(
  userId: string,
  weekStart: string,
): Promise<ServedWeek | null> {
  const existing = await db.query<{
    challenge_key: string;
    target: number;
    baseline: number | null;
  }>(
    `SELECT challenge_key, target, baseline
		FROM user_weekly_challenges
		WHERE user_id = $1 AND week_start = $2::date`,
    [userId, weekStart],
  );

  if (existing[0]) {
    const challenge = await getChallengeByKey(existing[0].challenge_key);
    // The catalog row was deactivated or renamed after being served. Nothing
    // sane to render, and re-picking would contradict the stamp.
    if (!challenge) return null;
    return {
      challenge,
      target: existing[0].target,
      baseline: existing[0].baseline,
      weekStart,
    };
  }

  const challenge = await selectChallengeForWeek(userId, weekStart);
  if (!challenge) return null;

  const baseline = await computeBaseline(userId, challenge.metric, weekStart);
  const resolved = resolveTarget(challenge, baseline);

  await db.query(
    `INSERT INTO user_weekly_challenges (user_id, week_start, challenge_key, target, baseline)
		VALUES ($1, $2::date, $3, $4, $5)
		ON CONFLICT (user_id, week_start) DO NOTHING`,
    [
      userId,
      weekStart,
      challenge.challenge_key,
      resolved.target,
      resolved.baseline,
    ],
  );

  // Re-read rather than trusting our own values: another request may have
  // stamped first, and the frozen row is the authority.
  return serveWeek(userId, weekStart);
}

// MARK: - Completion

export interface WeeklyCompletion {
  weekStart: string;
  challengeKey: string;
  title: string;
  target: number;
  finalValue: number;
}

/**
 * Award this week's challenge if the user has now met their target.
 *
 * Called from the workout-sync reward pass and the steps upsert. Unlike the
 * daily evaluator this recomputes the WHOLE week rather than looking at the
 * workouts that just arrived — every weekly metric is cumulative, so "what did
 * this upload add" isn't a question that can answer it.
 *
 * Returns non-null only for the caller that actually inserted the row, so the
 * completion push is sent exactly once no matter how many syncs race.
 */
export async function evaluateWeeklyChallengeForUser(
  userId: string,
): Promise<WeeklyCompletion | null> {
  const window = await weekWindowForUser(userId);

  // Cheap exit for the overwhelmingly common case: already done this week.
  const done = await db.query<{ ok: boolean }>(
    `SELECT EXISTS (
			SELECT 1 FROM user_weekly_challenge_completions
			WHERE user_id = $1 AND week_start = $2::date
		) AS ok`,
    [userId, window.weekStart],
  );
  if (done[0]?.ok) return null;

  const served = await serveWeek(userId, window.weekStart);
  if (!served) return null;

  const value = await measure(
    userId,
    served.challenge.metric,
    window.weekStart,
    minDate(window.weekEnd, window.localToday),
  );
  if (value < served.target) return null;

  const inserted = await db.query<{ id: string }>(
    `INSERT INTO user_weekly_challenge_completions
			(user_id, week_start, challenge_key, target, final_value)
		VALUES ($1, $2::date, $3, $4, $5)
		ON CONFLICT (user_id, week_start) DO NOTHING
		RETURNING id::text`,
    [
      userId,
      window.weekStart,
      served.challenge.challenge_key,
      served.target,
      value,
    ],
  );

  // Lost the race — the other caller owns the push.
  if (!inserted[0]) return null;

  const completion: WeeklyCompletion = {
    weekStart: window.weekStart,
    challengeKey: served.challenge.challenge_key,
    title: served.challenge.title,
    target: served.target,
    finalValue: value,
  };

  // Sent from here rather than the cron: this is the one moment we know the
  // insert happened, so it can't double-send. Fire-and-forget — a push failure
  // must not roll back a completion the user earned.
  notifyWeeklyCompletion(userId, completion).catch((error: any) => {
    console.error(
      "[WeeklyChallenges] Completion push failed:",
      error?.message ?? error,
    );
  });

  return completion;
}

/**
 * "You finished this week's challenge."
 *
 * Gated per device: `weekly_challenge_complete` is a new type string with no
 * handler on any shipped build, so an ungated send would be a banner that does
 * nothing when tapped.
 */
async function notifyWeeklyCompletion(
  userId: string,
  completion: WeeklyCompletion,
): Promise<void> {
  const [supported, allowed] = await Promise.all([
    userSupports(userId, CLIENT_FEATURES.weeklyChallengeV1),
    shouldSendNotification(userId, null, "weekly_challenge"),
  ]);
  if (!supported || !allowed) return;

  const streak = await getWeeklyStreak(userId, completion.weekStart);
  const body =
    streak.current > 1
      ? `${completion.title} done — ${streak.current} weeks in a row.`
      : `${completion.title} done. Nice work.`;

  await sendPush(userId, {
    title: "Weekly challenge complete",
    body,
    type: "weekly_challenge_complete",
    // String-valued throughout: shipped builds decode the inbox's data as
    // [String: String] and one number breaks the entire decode.
    data: {
      type: "weekly_challenge_complete",
      challenge_key: completion.challengeKey,
      week_start: completion.weekStart,
      final_value: String(completion.finalValue),
    },
  });
}

function minDate(a: string, b: string): string {
  return a < b ? a : b;
}

// MARK: - Streak

/**
 * Consecutive completed weeks ending at the most recent one, and the best run
 * ever. Adjacency is exactly seven days — the weekly counterpart to the daily
 * challenge streak.
 */
export async function getWeeklyStreak(
  userId: string,
  currentWeekStart?: string,
): Promise<{ current: number; best: number }> {
  const rows = await db.query<{ week_start: string }>(
    `SELECT week_start::text AS week_start
		FROM user_weekly_challenge_completions
		WHERE user_id = $1
		ORDER BY week_start DESC`,
    [userId],
  );
  if (rows.length === 0) return { current: 0, best: 0 };

  let current = 0;
  let best = 0;
  let run = 0;
  let previous: string | null = null;

  for (const row of rows) {
    if (previous === null || addDays(previous, -7) === row.week_start) {
      run++;
    } else {
      if (current === 0) current = run;
      run = 1;
    }
    best = Math.max(best, run);
    previous = row.week_start;
  }
  if (current === 0) current = run;

  // The leading run is only CURRENT if it reaches the present. Without this,
  // someone who completed twelve weeks straight and then stopped six months
  // ago is still told they're on a twelve-week streak.
  //
  // Last week counts as current: the week is still in progress, so not having
  // finished it yet is not a broken streak.
  if (currentWeekStart) {
    const newest = rows[0].week_start;
    const stillAlive =
      newest === currentWeekStart || newest === addDays(currentWeekStart, -7);
    if (!stillAlive) current = 0;
  }

  return { current, best };
}

// MARK: - Batched measurement (leaderboard)

/**
 * `measure`, for many users at once.
 *
 * The leaderboard needs every friend's value for the same metric and window;
 * calling `measure` per friend would fire one query per person. These are the
 * same predicates grouped by `user_id` — keep them in lockstep with the
 * single-user arms above, since a divergence would make your own number on the
 * board disagree with your own progress ring.
 */
export async function measureBatch(
  userIds: string[],
  metric: WeeklyMetric,
  fromDate: string,
  toDate: string,
): Promise<Map<string, number>> {
  const result = new Map<string, number>();
  if (userIds.length === 0) return result;

  const params = [userIds, fromDate, toDate];
  const counted = countedWorkoutSql("w");
  const range = `w.user_id = ANY($1::text[]) AND w.local_date BETWEEN $2::date AND $3::date`;

  let sql: string;
  switch (metric) {
    case "total_distance":
      sql = `SELECT w.user_id, COALESCE(SUM(w.distance), 0) AS v
				FROM workouts w WHERE ${range} AND ${counted} GROUP BY w.user_id`;
      break;

    case "weekend_distance":
      sql = `SELECT w.user_id, COALESCE(SUM(w.distance), 0) AS v
				FROM workouts w
				WHERE ${range} AND ${counted} AND EXTRACT(DOW FROM w.local_date) IN (0, 6)
				GROUP BY w.user_id`;
      break;

    case "longest_single_workout":
      sql = `SELECT w.user_id, COALESCE(MAX(w.distance), 0) AS v
				FROM workouts w WHERE ${range} AND ${counted} GROUP BY w.user_id`;
      break;

    case "total_minutes":
      sql = `SELECT w.user_id, COALESCE(SUM(w.total_duration), 0) / 60.0 AS v
				FROM workouts w WHERE ${range} AND ${counted} GROUP BY w.user_id`;
      break;

    case "workout_count":
      sql = `SELECT w.user_id, COUNT(*) AS v
				FROM workouts w
				WHERE ${range} AND ${counted} AND w.distance >= 0.25
				GROUP BY w.user_id`;
      break;

    case "active_days":
      sql = `SELECT w.user_id, COUNT(DISTINCT w.local_date) AS v
				FROM workouts w
				WHERE ${range} AND ${counted} AND w.distance >= 0.25
				GROUP BY w.user_id`;
      break;

    case "mile_days":
      sql = `WITH day_totals AS (
					SELECT w.user_id, w.local_date, SUM(w.distance) AS miles
					FROM workouts w
					WHERE ${range} AND ${counted}
					GROUP BY w.user_id, w.local_date
				)
				SELECT dt.user_id, COUNT(*) AS v
				FROM day_totals dt
				JOIN users u ON u.user_id = dt.user_id
				WHERE dt.miles >= GREATEST(COALESCE(u.goal_miles, 1), 0.1)::double precision * ${DAILY_GOAL_TOLERANCE}
				GROUP BY dt.user_id`;
      break;

    case "total_steps":
      sql = `SELECT ds.user_id, COALESCE(SUM(ds.steps), 0) AS v
				FROM daily_steps ds
				WHERE ds.user_id = ANY($1::text[])
					AND ds.local_date BETWEEN $2::date AND $3::date
				GROUP BY ds.user_id`;
      break;

    case "early_workouts":
    case "late_workouts": {
      const test = metric === "early_workouts" ? "< 8" : ">= 20";
      sql = `SELECT w.user_id, COUNT(*) AS v
				FROM workouts w
				WHERE ${range} AND ${counted} AND w.distance >= 0.25
					AND EXTRACT(HOUR FROM (
						w.device_end_date
						- (COALESCE(w.total_duration, 0) || ' seconds')::interval
						+ (w.timezone_offset || ' minutes')::interval
					)) ${test}
				GROUP BY w.user_id`;
      break;
    }

    case "fast_mile_splits":
      sql = `SELECT w.user_id, COUNT(*) AS v
				FROM workout_splits ws
				JOIN workouts w ON w.workout_id = ws.workout_id
				WHERE ${range} AND ${counted}
					AND ${realMileSplitSql("ws.split_pace")}
					AND ws.split_pace <= 600
				GROUP BY w.user_id`;
      break;

    case "consecutive_active_days":
      // Same gaps-and-islands as the single-user arm, partitioned per user.
      // ASC row numbering pairs with (d - rn); reversing that silently returns
      // 1 for everyone.
      sql = `WITH days AS (
					SELECT DISTINCT w.user_id, w.local_date AS d
					FROM workouts w
					WHERE ${range} AND ${counted} AND w.distance >= 0.25
				),
				islands AS (
					SELECT user_id, d,
						d - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY d ASC))::int AS island
					FROM days
				),
				runs AS (
					SELECT user_id, island, COUNT(*) AS run
					FROM islands GROUP BY user_id, island
				)
				SELECT user_id, MAX(run) AS v FROM runs GROUP BY user_id`;
      break;
  }

  const rows = await db.query<{ user_id: string; v: string | number | null }>(
    sql,
    params,
  );
  for (const row of rows) {
    const value =
      row.v === null || row.v === undefined
        ? 0
        : typeof row.v === "number"
          ? row.v
          : parseFloat(row.v) || 0;
    result.set(row.user_id, value);
  }
  return result;
}

// MARK: - Friends leaderboard

export interface WeeklyLeaderboardEntry {
  user_id: string;
  username: string | null;
  first_name: string | null;
  profile_image_url: string | null;
  value: number;
  target: number;
  /** Progress against their OWN target — how the board is ranked. */
  percent: number;
  completed: boolean;
  rank: number;
  is_me: boolean;
}

/**
 * The viewer's friends, ranked on this week's challenge.
 *
 * Ranked by percent of each person's OWN target, because the targets differ —
 * that is the whole point of scaling them. Raw value breaks ties, then username
 * so the order is stable across reloads rather than shuffling on every fetch.
 *
 * Two deliberate exclusions:
 *   - Friends with no served row yet. They have no frozen target, and inventing
 *     one would show a number that changes the moment they open the app. The
 *     Monday cron stamps everyone it notifies, so the board fills in early.
 *   - Blocks, in both directions.
 *
 * Everyone is measured over the VIEWER's week window. Per-friend windows aren't
 * comparable and would make the board reorder itself as timezones roll over.
 */
export async function getWeeklyLeaderboard(
  userId: string,
  weekStart: string,
  weekEnd: string,
  challengeKey: string,
  metric: WeeklyMetric,
): Promise<WeeklyLeaderboardEntry[]> {
  const blocked = await getBlockedIds(userId);

  const participants = await db.query<{
    user_id: string;
    username: string | null;
    first_name: string | null;
    profile_image_url: string | null;
    target: number;
    completed: boolean;
  }>(
    `WITH circle AS (
			SELECT CASE WHEN f.user_id = $1 THEN f.friend_id ELSE f.user_id END AS uid
			FROM friendships f
			WHERE (f.user_id = $1 OR f.friend_id = $1) AND f.status = 'accepted'
			UNION
			SELECT $1
		)
		SELECT
			u.user_id,
			u.username,
			u.first_name,
			u.profile_image_url,
			uwc.target,
			EXISTS (
				SELECT 1 FROM user_weekly_challenge_completions c
				WHERE c.user_id = u.user_id AND c.week_start = $2::date
			) AS completed
		FROM circle
		JOIN users u ON u.user_id = circle.uid
		JOIN user_weekly_challenges uwc
			ON uwc.user_id = u.user_id
			AND uwc.week_start = $2::date
			AND uwc.challenge_key = $3
		WHERE NOT (u.user_id = ANY($4::text[]))
		LIMIT 200`,
    [userId, weekStart, challengeKey, blocked],
  );

  if (participants.length === 0) return [];

  const values = await measureBatch(
    participants.map((p) => p.user_id),
    metric,
    weekStart,
    weekEnd,
  );

  return participants
    .map((p) => {
      const value = values.get(p.user_id) ?? 0;
      return {
        user_id: p.user_id,
        username: p.username,
        first_name: p.first_name,
        profile_image_url: p.profile_image_url,
        value,
        target: p.target,
        percent: p.target > 0 ? Math.min(1, value / p.target) : 0,
        completed: p.completed,
        rank: 0,
        is_me: p.user_id === userId,
      };
    })
    .sort((a, b) => {
      if (b.percent !== a.percent) return b.percent - a.percent;
      if (b.value !== a.value) return b.value - a.value;
      return (a.username ?? "").localeCompare(b.username ?? "");
    })
    .slice(0, 50)
    .map((entry, index) => ({ ...entry, rank: index + 1 }));
}

// MARK: - Read models

function renderDescription(row: WeeklyChallengeRow, target: number): string {
  const formatted =
    row.target_step >= 1
      ? Math.round(target).toLocaleString("en-US")
      : target.toFixed(1);
  return row.description_template
    .replace("{target}", formatted)
    .replace("{unit}", row.unit);
}

export interface WeeklyChallengeResponse {
  week_start: string;
  week_end: string;
  days_left: number;
  challenge: {
    challenge_key: string;
    title: string;
    description: string;
    icon: string;
    gradient_start: string;
    gradient_end: string;
    metric: WeeklyMetric;
    unit: string;
  };
  target: number;
  baseline: number | null;
  progress: {
    value: number;
    percent: number;
    completed: boolean;
    completed_at: string | null;
  };
  streak: { current_weeks: number; best_weeks: number };
  friends: WeeklyLeaderboardEntry[];
  my_rank: number | null;
  /** Whose week window the board is measured over. Always the viewer's. */
  window_owner: "viewer";
  next_challenge: { title: string; icon: string; description: string } | null;
}

/** The full weekly-challenge payload for a user's own read. */
export async function getWeeklyChallengeForUser(
  userId: string,
): Promise<WeeklyChallengeResponse | null> {
  const window = await weekWindowForUser(userId);
  const served = await serveWeek(userId, window.weekStart);
  if (!served) return null;

  const [value, completion, streak, friends] = await Promise.all([
    measure(
      userId,
      served.challenge.metric,
      window.weekStart,
      minDate(window.weekEnd, window.localToday),
    ),
    db.query<{ completed_at: string }>(
      `SELECT completed_at::text AS completed_at
			FROM user_weekly_challenge_completions
			WHERE user_id = $1 AND week_start = $2::date`,
      [userId, window.weekStart],
    ),
    getWeeklyStreak(userId, window.weekStart),
    getWeeklyLeaderboard(
      userId,
      window.weekStart,
      window.weekEnd,
      served.challenge.challenge_key,
      served.challenge.metric,
    ),
  ]);

  const completed = completion.length > 0;
  const nextStart = addDays(window.weekStart, 7);
  const nextRow = await selectChallengeForWeek(userId, nextStart);

  return {
    week_start: window.weekStart,
    week_end: window.weekEnd,
    days_left: Math.max(0, daysBetween(window.localToday, window.weekEnd) + 1),
    challenge: {
      challenge_key: served.challenge.challenge_key,
      title: served.challenge.title,
      description: renderDescription(served.challenge, served.target),
      icon: served.challenge.icon,
      gradient_start: served.challenge.gradient_start,
      gradient_end: served.challenge.gradient_end,
      metric: served.challenge.metric,
      unit: served.challenge.unit,
    },
    target: served.target,
    baseline: served.baseline,
    progress: {
      value,
      percent: served.target > 0 ? Math.min(1, value / served.target) : 0,
      completed,
      completed_at: completion[0]?.completed_at ?? null,
    },
    streak: { current_weeks: streak.current, best_weeks: streak.best },
    friends,
    my_rank: friends.find((f) => f.is_me)?.rank ?? null,
    window_owner: "viewer",
    // Next week's target isn't frozen yet — and would move if we scaled it now
    // — so the preview names the challenge without promising a number.
    next_challenge: nextRow
      ? {
          title: nextRow.title,
          icon: nextRow.icon,
          description: nextRow.description_template
            .replace("{target}", "…")
            .replace("{unit}", nextRow.unit),
        }
      : null,
  };
}

function daysBetween(from: string, to: string): number {
  const parse = (ymd: string) => {
    const [y, m, d] = ymd.split("-").map((n) => parseInt(n, 10));
    return Date.UTC(y, m - 1, d);
  };
  return Math.round((parse(to) - parse(from)) / 86400000);
}

export interface WeeklyHistoryItem {
  week_start: string;
  challenge_key: string;
  title: string;
  icon: string;
  gradient_start: string;
  gradient_end: string;
  unit: string;
  target: number;
  final_value: number | null;
  completed: boolean;
}

/**
 * Past weeks, newest first.
 *
 * Driven by what was SERVED, so each row reports the target that user was
 * actually set. Weeks with no served row are omitted rather than reconstructed
 * — the user saw nothing that week, and inventing a target they were never
 * given would be a worse answer than silence.
 */
export async function getWeeklyHistory(
  userId: string,
  limit = 26,
): Promise<WeeklyHistoryItem[]> {
  const rows = await db.query<{
    week_start: string;
    challenge_key: string;
    title: string;
    icon: string;
    gradient_start: string;
    gradient_end: string;
    unit: string;
    target: number;
    final_value: number | null;
  }>(
    `SELECT
			uwc.week_start::text AS week_start,
			uwc.challenge_key,
			wc.title,
			wc.icon,
			wc.gradient_start,
			wc.gradient_end,
			wc.unit,
			uwc.target,
			c.final_value
		FROM user_weekly_challenges uwc
		JOIN weekly_challenges wc ON wc.challenge_key = uwc.challenge_key
		LEFT JOIN user_weekly_challenge_completions c
			ON c.user_id = uwc.user_id AND c.week_start = uwc.week_start
		WHERE uwc.user_id = $1
		ORDER BY uwc.week_start DESC
		LIMIT $2`,
    [userId, Math.min(Math.max(limit, 1), 104)],
  );

  return rows.map((row) => ({
    ...row,
    completed: row.final_value !== null,
  }));
}

// MARK: - Catalog seed

/**
 * The launch catalog.
 *
 * Twelve, so a challenge comes round roughly quarterly rather than feeling like
 * a short loop. Every metric is computable from data the app already collects.
 *
 * `base_target` is the new-user number AND the floor; `target_ceiling` is the
 * absolute cap however strong the user is. Icons are all SF Symbols 5 or
 * earlier — the app targets iOS 17, where a newer symbol renders as a blank box
 * rather than falling back.
 *
 * Copy states distances and counts only. Never health outcomes (App Review
 * 1.4.1).
 */
const WEEKLY_CATALOG: Array<
  Omit<WeeklyChallengeRow, "scale_min_multiplier" | "scale_max_multiplier"> & {
    scale_min_multiplier?: number;
    scale_max_multiplier?: number;
    /** Defaults to true; false keeps a row out of the rotation entirely. */
    active?: boolean;
  }
> = [
  {
    challenge_key: "week_of_miles",
    title: "Week of Miles",
    description_template: "Cover {target} miles this week.",
    icon: "figure.run",
    gradient_start: "4ECDC4",
    gradient_end: "44A08D",
    metric: "total_distance",
    unit: "miles",
    base_target: 10,
    scale_multiplier: 1.1,
    target_ceiling: 60,
    target_step: 0.5,
    rotation_index: 0,
  },
  {
    challenge_key: "perfect_week",
    title: "Perfect Week",
    description_template: "Hit your daily goal on {target} of 7 days.",
    icon: "checkmark.seal.fill",
    gradient_start: "F7971E",
    gradient_end: "FFD200",
    metric: "mile_days",
    unit: "days",
    base_target: 5,
    scale_multiplier: 1.1,
    target_ceiling: 7,
    target_step: 1,
    rotation_index: 1,
  },
  {
    challenge_key: "show_up",
    title: "Show Up",
    description_template: "Get a workout in on {target} different days.",
    icon: "calendar",
    gradient_start: "667EEA",
    gradient_end: "764BA2",
    metric: "active_days",
    unit: "days",
    base_target: 4,
    scale_multiplier: 1.1,
    target_ceiling: 7,
    target_step: 1,
    rotation_index: 2,
  },
  {
    challenge_key: "long_haul",
    title: "Long Haul",
    description_template: "Log one workout of {target} miles or more.",
    icon: "arrow.up.right",
    gradient_start: "C33764",
    gradient_end: "1D2671",
    metric: "longest_single_workout",
    unit: "miles",
    base_target: 3,
    scale_multiplier: 1.15,
    target_ceiling: 20,
    target_step: 0.5,
    rotation_index: 3,
  },
  {
    challenge_key: "step_mountain",
    title: "Step Mountain",
    description_template: "Take {target} steps this week.",
    icon: "shoeprints.fill",
    gradient_start: "43C6AC",
    gradient_end: "191654",
    metric: "total_steps",
    unit: "steps",
    base_target: 50000,
    scale_multiplier: 1.1,
    target_ceiling: 200000,
    target_step: 1000,
    rotation_index: 4,
  },
  {
    challenge_key: "early_birds",
    title: "Early Birds",
    description_template: "Finish {target} workouts before 8 AM.",
    icon: "sunrise.fill",
    gradient_start: "FF6B6B",
    gradient_end: "FF8E53",
    metric: "early_workouts",
    unit: "runs",
    base_target: 2,
    scale_multiplier: 1.2,
    target_ceiling: 10,
    target_step: 1,
    rotation_index: 5,
  },
  {
    challenge_key: "night_owls",
    title: "Night Owls",
    description_template: "Finish {target} workouts after 8 PM.",
    icon: "moon.stars.fill",
    gradient_start: "2C3E50",
    gradient_end: "4CA1AF",
    metric: "late_workouts",
    unit: "runs",
    base_target: 2,
    scale_multiplier: 1.2,
    target_ceiling: 10,
    target_step: 1,
    rotation_index: 6,
  },
  {
    challenge_key: "weekend_warrior",
    title: "Weekend Warrior",
    description_template: "Cover {target} miles across Saturday and Sunday.",
    icon: "flame.fill",
    gradient_start: "FF512F",
    gradient_end: "F09819",
    metric: "weekend_distance",
    unit: "miles",
    base_target: 4,
    scale_multiplier: 1.1,
    target_ceiling: 30,
    target_step: 0.5,
    rotation_index: 7,
  },
  {
    challenge_key: "time_on_feet",
    title: "Time on Feet",
    description_template: "Spend {target} minutes moving.",
    icon: "clock.fill",
    gradient_start: "56CCF2",
    gradient_end: "2F80ED",
    metric: "total_minutes",
    unit: "minutes",
    base_target: 150,
    scale_multiplier: 1.1,
    target_ceiling: 900,
    target_step: 5,
    rotation_index: 8,
  },
  {
    challenge_key: "speed_week",
    title: "Speed Week",
    description_template: "Log {target} miles at a sub-10:00 pace.",
    icon: "bolt.fill",
    gradient_start: "F953C6",
    gradient_end: "B91D73",
    metric: "fast_mile_splits",
    unit: "miles",
    base_target: 2,
    scale_multiplier: 1.2,
    target_ceiling: 15,
    target_step: 1,
    rotation_index: 9,
  },
  {
    challenge_key: "volume_up",
    title: "Volume Up",
    description_template: "Log {target} separate workouts.",
    icon: "square.stack.fill",
    gradient_start: "8E2DE2",
    gradient_end: "4A00E0",
    metric: "workout_count",
    unit: "runs",
    base_target: 5,
    scale_multiplier: 1.1,
    target_ceiling: 25,
    target_step: 1,
    rotation_index: 10,
  },
  {
    challenge_key: "back_to_back",
    title: "Back to Back",
    description_template: "String together {target} days in a row.",
    icon: "link",
    gradient_start: "11998E",
    gradient_end: "38EF7D",
    metric: "consecutive_active_days",
    unit: "days",
    base_target: 3,
    scale_multiplier: 1.15,
    target_ceiling: 7,
    target_step: 1,
    rotation_index: 11,
  },
  // Off-rotation substitute — see STEPS_SUBSTITUTE_KEY. active = false keeps it
  // out of getCatalog(), so it is only ever reachable by explicit key.
  {
    challenge_key: STEPS_SUBSTITUTE_KEY,
    title: "Move More",
    description_template: "Get a workout in on {target} different days.",
    icon: "figure.walk",
    gradient_start: "43C6AC",
    gradient_end: "191654",
    metric: "active_days",
    unit: "days",
    base_target: 4,
    scale_multiplier: 1.1,
    target_ceiling: 7,
    target_step: 1,
    rotation_index: 200,
    active: false,
  },
];

/**
 * Seed the catalog, idempotently, AFTER `listen()`.
 *
 * Deliberately not a migration: migrations run at boot inside a 30s statement
 * timeout and a failure there is never recorded, so it retries on every boot —
 * a boot loop with no shell to escape it. Here a failure logs and the server
 * keeps serving. It also means adding a thirteenth challenge, or fixing a typo
 * in a description, is a code change rather than a migration.
 *
 * The metric CHECK is (re)applied here for the same reason.
 */
export async function seedWeeklyChallenges(): Promise<void> {
  try {
    const metrics = [...new Set(WEEKLY_CATALOG.map((row) => row.metric))].map(
      (m) => `'${m}'`,
    );

    await db.query(
      `ALTER TABLE weekly_challenges DROP CONSTRAINT IF EXISTS weekly_challenges_metric_check`,
    );
    await db.query(
      `ALTER TABLE weekly_challenges
			ADD CONSTRAINT weekly_challenges_metric_check
			CHECK (metric = ANY (ARRAY[${metrics.join(", ")}]::text[]))`,
    );

    for (const row of WEEKLY_CATALOG) {
      await db.query(
        `INSERT INTO weekly_challenges (
					challenge_key, title, description_template, icon,
					gradient_start, gradient_end, metric, unit,
					base_target, scale_multiplier, scale_min_multiplier,
					scale_max_multiplier, target_ceiling, target_step,
					active, rotation_index
				) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$16,$15)
				ON CONFLICT (challenge_key) DO UPDATE SET
					title = EXCLUDED.title,
					description_template = EXCLUDED.description_template,
					icon = EXCLUDED.icon,
					gradient_start = EXCLUDED.gradient_start,
					gradient_end = EXCLUDED.gradient_end,
					metric = EXCLUDED.metric,
					unit = EXCLUDED.unit,
					base_target = EXCLUDED.base_target,
					scale_multiplier = EXCLUDED.scale_multiplier,
					scale_min_multiplier = EXCLUDED.scale_min_multiplier,
					scale_max_multiplier = EXCLUDED.scale_max_multiplier,
					target_ceiling = EXCLUDED.target_ceiling,
					target_step = EXCLUDED.target_step,
					active = EXCLUDED.active`,
        [
          row.challenge_key,
          row.title,
          row.description_template,
          row.icon,
          row.gradient_start,
          row.gradient_end,
          row.metric,
          row.unit,
          row.base_target,
          row.scale_multiplier,
          row.scale_min_multiplier ?? 1,
          row.scale_max_multiplier ?? 2.5,
          row.target_ceiling,
          row.target_step,
          row.rotation_index,
          row.active ?? true,
        ],
      );
    }
    console.log(`[WeeklyChallenges] Seeded ${WEEKLY_CATALOG.length} rows.`);
  } catch (error: any) {
    // Never fatal: the server is already listening, and a stale catalog beats
    // a crash loop.
    console.error("[WeeklyChallenges] Seed failed:", error?.message ?? error);
  }
}
