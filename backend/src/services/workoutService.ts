import { Workout } from "../types/workouts.js";
import {
  MIN_PLAUSIBLE_MILE_SECONDS,
  MAX_PLAUSIBLE_MILE_SECONDS,
} from "./mileTime.js";
import { PostgresService } from "./DbService.js";
import { VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL } from "./visibilityService.js";
import {
  coverageActiveFor,
  computeCoveredStreak,
  computeStreakEras,
  type StreakEra,
} from "./streakFeatureCore.js";

const db = PostgresService.getInstance();

/**
 * The ghost-race columns for one workout's upsert, as
 * `[margin, target, friendUserId]`.
 *
 * `margin` is SIGNED: positive = won by that many seconds, negative = lost by
 * them. It is stamped for every completed race, not just wins, because a race
 * you lost by two seconds is the most motivating thing the feature can show you
 * and it used to vanish without trace.
 *
 * The consequence, and the reason this comment is long: `IS NOT NULL` no longer
 * means "won". Anything counting WINS must say `> 0` — the medal aggregate (both
 * the count and the MAX, which would otherwise return a negative for someone who
 * has only lost), and the "your ghost was caught" push.
 *
 * Implausible claims are dropped to null rather than stored: bounds mirror the
 * client's `GhostTarget.isPlausible` (4:01…40:00), and no margin in either
 * direction can exceed a whole plausible mile.
 *
 * `friendUserId` is present only when the ghost was a FRIEND's mile. It is
 * client-asserted and NOT validated here — it is validated where it matters,
 * at notify time in `notifyGhostsBeaten`, which re-checks the friendship and
 * the block state before telling anyone anything. Storing an unverified id is
 * harmless; pushing on one would be a spoofing vector.
 */
function ghostRaceParams(
  workout: Workout,
): [number | null, number | null, string | null] {
  const margin = Number(workout.ghostMarginSeconds);
  const target = Number(workout.ghostTargetSeconds);
  const ok =
    Number.isFinite(margin) &&
    Number.isFinite(target) &&
    margin !== 0 &&
    target >= MIN_PLAUSIBLE_MILE_SECONDS &&
    target <= MAX_PLAUSIBLE_MILE_SECONDS &&
    Math.abs(margin) <= MAX_PLAUSIBLE_MILE_SECONDS;
  if (!ok) return [null, null, null];
  const friend =
    typeof workout.ghostFriendUserId === "string" &&
    workout.ghostFriendUserId.length > 0 &&
    workout.ghostFriendUserId !== workout.workoutId
      ? workout.ghostFriendUserId
      : null;
  return [margin, target, friend];
}

export async function uploadWorkouts(
  userId: string,
  workouts: Workout[],
): Promise<string[]> {
  // Ownership guard: workout ids are visible to friends in feed payloads, so a
  // crafted upload could otherwise ON CONFLICT into ANOTHER user's row (and its
  // splits/route) and corrupt their data. Drop any id already owned by someone
  // else before building the transaction; the DO UPDATE below is additionally
  // guarded as a race backstop.
  // Days whose feed roles this upload could invalidate. Seeded with the days
  // the incoming workouts BELONG TO now (below) plus, from the lookup here, the
  // days they used to belong to: the DO UPDATE sets local_date = EXCLUDED, so a
  // re-upload can move a workout to another day and strand a stale anchor —
  // possibly one whose workout no longer lives in that day at all.
  const affectedDays = new Set<string>();
  if (workouts.length > 0) {
    // Ownership guard: workout ids are visible to friends in feed payloads, so a
    // crafted upload could otherwise ON CONFLICT into ANOTHER user's row (and its
    // splits/route) and corrupt their data. Drop any id already owned by someone
    // else before building the transaction; the DO UPDATE below is additionally
    // guarded as a race backstop.
    const existing = await db.query<{
      workout_id: string;
      user_id: string;
      local_date: string;
    }>(
      `SELECT workout_id, user_id, local_date::text AS local_date FROM workouts
			WHERE workout_id = ANY($1::text[])`,
      [workouts.map((w) => w.workoutId)],
    );
    const foreignIds = new Set(
      existing.filter((r) => r.user_id !== userId).map((r) => r.workout_id),
    );
    for (const row of existing) {
      if (row.user_id === userId) affectedDays.add(row.local_date);
    }
    if (foreignIds.size > 0) {
      console.warn(
        `[uploadWorkouts] Dropping ${foreignIds.size} workout(s) owned by another user (uploader ${userId})`,
      );
      workouts = workouts.filter((w) => !foreignIds.has(w.workoutId));
      if (workouts.length === 0) return [];
    }
  }

  const workoutQuery = `
      INSERT INTO workouts (
        user_id,
        workout_id,
        distance,
        local_date,
        date,
        timezone_offset,
        workout_type,
        device_end_date,
        calories,
        total_duration,
        moving_seconds,
        ghost_margin_seconds,
        ghost_target_seconds,
        ghost_friend_user_id,
        source,
        source_bundle_id,
        exclusion_reason,
        speed_flagged
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
      ON CONFLICT (workout_id)
      DO UPDATE SET
        distance = EXCLUDED.distance,
        local_date = EXCLUDED.local_date,
        date = EXCLUDED.date,
        timezone_offset = EXCLUDED.timezone_offset,
        workout_type = EXCLUDED.workout_type,
        device_end_date = EXCLUDED.device_end_date,
        calories = EXCLUDED.calories,
        total_duration = EXCLUDED.total_duration,
        moving_seconds = EXCLUDED.moving_seconds,
        -- COALESCE, not overwrite: a re-upload from a path that doesn't carry
        -- HealthKit metadata (fullSync, recalibrate) must never erase a win
        -- the tracker already recorded. Same reasoning as workout_routes.
        ghost_margin_seconds = COALESCE(EXCLUDED.ghost_margin_seconds, workouts.ghost_margin_seconds),
        ghost_target_seconds = COALESCE(EXCLUDED.ghost_target_seconds, workouts.ghost_target_seconds),
        ghost_friend_user_id = COALESCE(EXCLUDED.ghost_friend_user_id, workouts.ghost_friend_user_id),
        source = CASE
          WHEN workouts.source IN ('manual', 'edited') THEN workouts.source
          ELSE EXCLUDED.source
        END,
        -- COALESCE for the same reason as the ghost columns: a re-upload from a
        -- path that doesn't carry the HealthKit source (an older client, a
        -- recalibrate) must not erase provenance we already recorded. Losing it
        -- would silently un-dedupe the day.
        source_bundle_id = COALESCE(EXCLUDED.source_bundle_id, workouts.source_bundle_id),
        -- Recompute the speed classification from the latest figures, but never
        -- clear a user soft-delete (deleted_at is intentionally not updated here).
        exclusion_reason = EXCLUDED.exclusion_reason,
        speed_flagged = EXCLUDED.speed_flagged
      WHERE workouts.user_id = $1
      RETURNING workout_id, (xmax = 0) AS inserted
    `;

  const splitQuery = `
        INSERT INTO workout_splits (workout_id, split_number, split_duration, split_distance, split_pace)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (workout_id, split_number)
        DO UPDATE SET
			split_duration = EXCLUDED.split_duration,
			split_distance = EXCLUDED.split_distance,
			split_pace = EXCLUDED.split_pace
      `;

  const routeQuery = `
        INSERT INTO workout_routes (workout_id, route, point_count, updated_at)
        VALUES ($1, $2::jsonb, $3, NOW())
        ON CONFLICT (workout_id)
        DO UPDATE SET
			route = EXCLUDED.route,
			point_count = EXCLUDED.point_count,
			updated_at = NOW()
      `;

  for (const workout of workouts) affectedDays.add(workout.localDate);

  const upserts = workouts.flatMap((workout: Workout) => {
    const speed = classifyWorkoutSpeed(workout.distance, workout.totalDuration);
    const route = sanitizeRoute(workout.route);
    return [
      {
        query: workoutQuery,
        params: [
          userId,
          workout.workoutId,
          workout.distance,
          workout.localDate,
          workout.date,
          workout.timezoneOffset,
          workout.workoutType,
          workout.deviceEndDate,
          workout.calories,
          workout.totalDuration,
          // Display-pace divisor: must be a sane number of seconds, never
          // exceeding elapsed (a malformed value must not 500 the sync or
          // mint faster-than-elapsed pace).
          Number.isFinite(workout.movingSeconds) &&
          (workout.movingSeconds as number) > 0
            ? Math.min(workout.movingSeconds as number, workout.totalDuration)
            : null,
          // Ghost race — stamped only on a WIN, so presence is the win. Bounds
          // mirror the client's GhostTarget.isPlausible (2:00…40:00) and a
          // margin can never exceed the ghost it beat; anything else is
          // dropped rather than trusted.
          ...ghostRaceParams(workout),
          workout.source || "healthkit",
          // Which app wrote this into HealthKit. Absent on older clients, which
          // simply never participate in cross-app dedup.
          typeof workout.sourceBundleId === "string" &&
          workout.sourceBundleId.trim() !== ""
            ? workout.sourceBundleId.trim().slice(0, 255)
            : null,
          speed.exclusionReason,
          speed.speedFlagged,
        ],
      },
      ...workout.splits.map((split) => ({
        query: splitQuery,
        params: [
          workout.workoutId,
          split.splitNumber,
          split.duration,
          split.distance,
          split.pace,
        ],
      })),
      ...(route
        ? [
            {
              query: routeQuery,
              params: [workout.workoutId, JSON.stringify(route), route.length],
            },
          ]
        : []),
    ];
  });

  // Upserts and reclassification go in ONE transaction, behind the per-user
  // advisory lock. Splitting them would leave a window where new rows sit at the
  // 'extra' default — i.e. every junk walk and every pre-mile segment visible as
  // its own card — and if the process died in that window they'd stay that way.
  await db.transaction([
    advisoryLockStatement(userId),
    ...upserts,
    // Duplicate detection runs between the upsert and the feed roles, and the
    // order is load-bearing both ways — see duplicateExclusionStatements.
    ...[...affectedDays].flatMap((localDate) => [
      ...duplicateExclusionStatements(userId, localDate),
      ...feedRoleStatements(userId, localDate),
    ]),
  ]);

  return workouts.map((w) => w.workoutId);
}

// A trace only needs enough fidelity to draw a small map; clients downsample
// before upload and this is the server-side backstop.
const MAX_ROUTE_POINTS = 300;

/**
 * Validate + normalize an uploaded GPS trace. Returns null (skip storage) for
 * anything that isn't a plausible [[lat, lng], ...] polyline with >= 2 points.
 * Coordinates are rounded to 5 decimals (~1m) and long traces are downsampled.
 */
function sanitizeRoute(route: unknown): [number, number][] | null {
  if (!Array.isArray(route) || route.length < 2) return null;
  const points: [number, number][] = [];
  for (const p of route) {
    if (!Array.isArray(p) || p.length < 2) return null;
    const lat = Number(p[0]);
    const lng = Number(p[1]);
    if (
      !Number.isFinite(lat) ||
      !Number.isFinite(lng) ||
      Math.abs(lat) > 90 ||
      Math.abs(lng) > 180
    ) {
      return null;
    }
    points.push([
      Math.round(lat * 100000) / 100000,
      Math.round(lng * 100000) / 100000,
    ]);
  }
  if (points.length <= MAX_ROUTE_POINTS) return points;
  const stride = (points.length - 1) / (MAX_ROUTE_POINTS - 1);
  const sampled: [number, number][] = [];
  for (let i = 0; i < MAX_ROUTE_POINTS; i++) {
    sampled.push(points[Math.round(i * stride)]);
  }
  return sampled;
}

/**
 * Classify a workout by its average speed to catch "left tracking on in the car".
 * A human can't run/walk a mile faster than ~15 mph (the mile world record), and
 * only running/walking workouts ever reach us, so:
 *   - >= 20 mph  → physically impossible on foot → auto-exclude (does NOT count).
 *                  Conservative on purpose: zero risk of rejecting a real run.
 *   - 13–20 mph  → suspicious but theoretically human → flag for the user to
 *                  review/delete; still counts.
 * Guards against missing/zero data (returns "not flagged").
 */
const VEHICLE_EXCLUDE_MPH = 20;
const VEHICLE_FLAG_MPH = 13;

function classifyWorkoutSpeed(
  distance: number | null | undefined,
  totalDuration: number | null | undefined,
): { exclusionReason: string | null; speedFlagged: boolean } {
  const d = Number(distance);
  const secs = Number(totalDuration);
  if (!isFinite(d) || !isFinite(secs) || d <= 0 || secs <= 0) {
    return { exclusionReason: null, speedFlagged: false };
  }
  const mph = (d * 3600) / secs;
  if (mph >= VEHICLE_EXCLUDE_MPH) {
    return { exclusionReason: "vehicle_speed", speedFlagged: true };
  }
  if (mph >= VEHICLE_FLAG_MPH) {
    return { exclusionReason: null, speedFlagged: true };
  }
  return { exclusionReason: null, speedFlagged: false };
}

/**
 * The floor a workout must clear to earn a feed card of its own.
 *
 * This is a FEED rule, not a counting rule. A 0.02-mile phantom still adds to
 * today's miles, can still complete a streak day, and still shows on the user's
 * own dashboard so they can delete it — it just doesn't get to post. That's why
 * this is separate from `exclusion_reason`, which really does stop a workout
 * counting and is read by streaks, challenges, badges and competitions.
 *
 * Anything below either bound is almost always an accident: a workout started
 * and stopped by mistake, or a stray auto-detected sample. "0.00 mi in 3
 * seconds" is the canonical case.
 *
 * iOS mirrors these in `WorkoutFeedFloor` (Utils/Extensions.swift) the same way
 * it mirrors DAILY_GOAL_TOLERANCE — keep them in sync.
 */
export const FEED_MIN_DISTANCE = 0.05; // miles
export const FEED_MIN_DURATION = 30; // seconds

/**
 * Miles a day must total before it earns a feed card — the same absolute 0.95
 * the streak rule uses (`HAVING SUM(distance) >= 0.95` in getActiveStreak,
 * refreshCurrentStreak and computeCoveredStreak), so "a card appeared" means
 * "this day counted for your streak".
 *
 * Deliberately NOT `goal_miles * DAILY_GOAL_TOLERANCE`: feed_role is stored, and
 * a per-user goal would make every stored role go stale the moment that goal
 * changed. `goal_miles` has defaulted to 1.0 since launch and no endpoint
 * writes it, so today the two are the same number anyway — this just doesn't
 * inherit the staleness problem if that ever changes.
 */
export const FEED_QUALIFYING_DISTANCE = 0.95;

/**
 * How a workout shows up in the feed. See the `feed_role` column comment in
 * db/drizzle/schema.ts for what each value means.
 */
export type FeedRole = "hidden" | "rolled_up" | "daily_mile" | "extra";

/**
 * Is this workout substantial enough to surface socially at all?
 *
 * The in-memory twin of the SQL predicate in `feedRoleStatements`, for callers
 * holding an unsaved payload — notification fan-out decides before the row's
 * feed_role has been read back. Both must agree, or friends get pushed about a
 * workout that then has no card to land on.
 */
export function isFeedWorthyWorkout(
  distance: number | null | undefined,
  totalDuration: number | null | undefined,
): boolean {
  const d = Number(distance);
  const secs = Number(totalDuration);
  if (!isFinite(d) || !isFinite(secs)) return false;
  return d >= FEED_MIN_DISTANCE && secs >= FEED_MIN_DURATION;
}

/**
 * The classification itself, as statements ready to splice into a caller's
 * transaction. `feedRoleStatements` is the ONLY place feed_role is ever
 * written — recomputeFeedRolesForDay just runs these standalone.
 *
 * Always reclassifies the WHOLE day rather than patching the row that changed,
 * because the day's shape is what decides the roles: a Watch workout that syncs
 * late can land *before* the current anchor and take its place, and deleting a
 * segment can drop the day back under the mile and hide it entirely.
 *
 * Four things this gets right that a naive running-sum doesn't:
 *
 *  - **Junk counts toward the day, it just can't anchor it.** The running sum
 *    includes sub-floor workouts, so the day total here equals the SUM(distance)
 *    every other surface reports (profile, leaderboard, streak). Excluding them
 *    would make the feed card read 1.02 mi on a day everything else calls
 *    1.06 mi. They're barred from being the anchor and get no segment row.
 *  - **The anchor is always substantive.** 0.98 mi run + a 0.03 phantom means
 *    the phantom is the row that crosses 0.95; anchoring there would headline
 *    the day with a card for an accident. The anchor is the last real workout at
 *    or before the crossing point.
 *  - **Ranks, not timestamps.** Phone and Watch write identical
 *    `device_end_date` values often enough that comparing timestamps classifies
 *    two rows the same way. ROW_NUMBER breaks the tie on workout_id.
 *  - **The anchor is sticky.** A backdated workout arriving later would
 *    otherwise move the anchor to an earlier row, dragging the card's sort_ts
 *    backwards — past the point a scrolling viewer already read, so the day
 *    silently disappears for them. An existing anchor is kept as long as it's
 *    still real, still present, and still at/before the crossing point.
 *
 * Scoped to one day, so it's a small indexed write
 * (idx_workouts_user_local_date) — cheap enough to run on every mutation.
 */
function feedRoleStatements(
  userId: string,
  localDate: string,
): { query: string; params: any[] }[] {
  const params = [
    userId,
    localDate,
    FEED_MIN_DISTANCE,
    FEED_MIN_DURATION,
    FEED_QUALIFYING_DISTANCE,
  ];
  return [
    {
      // Rows that can't be in the feed at all. Kept separate from the pass
      // below, whose `day` CTE only sees live rows.
      query: `
	UPDATE workouts SET feed_role = 'hidden'
	WHERE user_id = $1 AND local_date = $2::date
		AND (deleted_at IS NOT NULL OR exclusion_reason IS NOT NULL)
		AND feed_role <> 'hidden'`,
      params: [userId, localDate],
    },
    {
      query: `
	WITH day AS (
		SELECT
			workout_id,
			feed_role,
			(distance >= $3 AND total_duration >= $4) AS substantive,
			ROW_NUMBER() OVER (ORDER BY device_end_date, workout_id) AS rn,
			SUM(distance) OVER (
				ORDER BY device_end_date, workout_id ROWS UNBOUNDED PRECEDING
			) AS cumulative
		FROM workouts
		WHERE user_id = $1 AND local_date = $2::date
			AND deleted_at IS NULL AND exclusion_reason IS NULL
	),
	-- Where the day reached the mile. NULL means it never did.
	crossing AS (
		SELECT MIN(rn) AS rn FROM day WHERE cumulative + 1e-9 >= $5
	),
	-- Keep the anchor we already have, if it's still valid (see stickiness).
	sticky AS (
		SELECT MAX(rn) AS rn FROM day
		WHERE feed_role = 'daily_mile' AND substantive
			AND rn <= (SELECT rn FROM crossing)
	),
	-- Otherwise the last real workout at or before the crossing point.
	fresh AS (
		SELECT MAX(rn) AS rn FROM day
		WHERE substantive AND rn <= (SELECT rn FROM crossing)
	),
	anchor AS (
		SELECT COALESCE((SELECT rn FROM sticky), (SELECT rn FROM fresh)) AS rn
	),
	roles AS (
		SELECT d.workout_id, CASE
			-- Day never reached the mile, or got there only on junk: show
			-- nothing. (The second case counts for the streak but has no real
			-- workout to put on a card.)
			WHEN (SELECT rn FROM anchor) IS NULL THEN 'hidden'
			WHEN NOT d.substantive THEN 'hidden'
			WHEN d.rn = (SELECT rn FROM anchor) THEN 'daily_mile'
			WHEN d.rn < (SELECT rn FROM anchor) THEN 'rolled_up'
			ELSE 'extra'
		END AS role
		FROM day d
	)
	UPDATE workouts w SET feed_role = r.role
	FROM roles r
	WHERE w.workout_id = r.workout_id AND w.user_id = $1
		-- Skip no-op rewrites so a re-sync of an unchanged day costs no row
		-- versions and no index churn.
		AND w.feed_role IS DISTINCT FROM r.role`,
      params,
    },
  ];
}

/**
 * Cross-app duplicate detection.
 *
 * HealthKit is the integration layer for every third-party platform: Strava,
 * Garmin Connect, Whoop, Oura, Peloton and the rest all write workouts into
 * Apple Health, and the app reads them with no source filter. That's what makes
 * "connect your other apps" possible at all — but it also means a user with two
 * of them connected hands us the SAME real-world run twice, as two HKWorkouts
 * with two different UUIDs. UUID dedup can't see it, so both rows count: double
 * miles, double progress toward the daily mile, inflated leaderboards and
 * competition scores.
 *
 * A pair is the same run when all three hold:
 *   - **Different apps.** Two workouts from the SAME bundle id are never
 *     duplicates — that's a user legitimately logging two sessions, and one app
 *     doesn't double-write itself. A null bundle id (pre-feature rows, older
 *     clients) matches nothing; unknown provenance fails open.
 *   - **They genuinely overlap in time**, by at least half of the shorter
 *     workout. Bare interval intersection is too weak: a cooldown walk that
 *     clips the end of a run shares a minute without being the same activity.
 *   - **Their distances agree**, within 20% of the longer one (floor 0.1 mi).
 *     Watch GPS and phone GPS disagree by a few percent on the same route.
 *
 * The survivor is deterministic and prefers the richest copy: has a GPS route →
 * uploaded first → lowest workout_id. Losers get `duplicate_of` set.
 *
 * Chains are avoided by resolving in two passes — a row can only ever be marked
 * a duplicate OF a row that is not itself a duplicate. A duplicate that somehow
 * overlaps no keeper is left unmarked rather than guessed at (fail open: the
 * failure mode of over-counting is a wrong number, of under-counting is a
 * broken streak).
 */
const DUPLICATE_EXCLUSION_REASON = "duplicate_source";
/** Share of the SHORTER workout that must overlap before it's the same run. */
const DUPLICATE_MIN_OVERLAP_RATIO = 0.5;
/** How far two measurements of one route may disagree (fraction of the longer). */
const DUPLICATE_DISTANCE_TOLERANCE = 0.2;
/** Absolute floor for the above, so short walks aren't held to a few feet. */
const DUPLICATE_DISTANCE_FLOOR = 0.1;

/**
 * Is cross-app duplicate EXCLUSION live?
 *
 * Kill switch, default OFF (env flags are kill switches, never the safety
 * mechanism — see .claude/rules/backend.md). Detection still runs and still
 * populates `duplicate_of` while it's off, so the flag can be flipped on only
 * after diffing what it would do against real data. Flipping it back off
 * unwinds every exclusion it applied on the next sync of each day.
 */
function duplicateExclusionEnabled(): boolean {
  const v = (process.env.WORKOUT_DEDUPE ?? "").toLowerCase();
  return v === "1" || v === "true" || v === "on";
}

/**
 * The detection + exclusion pass, as statements ready to splice into a caller's
 * transaction. Runs on the whole `(user, local_date)` for the same reason
 * `feedRoleStatements` does: which copy survives depends on the day's shape, and
 * a late Watch sync can land a better copy after the one we already kept.
 *
 * MUST run AFTER the upsert and BEFORE `feedRoleStatements`:
 *   - after, because the upsert resets `exclusion_reason` to the per-workout
 *     speed classification on every re-upload, which would wipe a duplicate mark;
 *   - before, because feed roles hide anything with an `exclusion_reason`, so
 *     duplicates drop out of the feed for free.
 *
 * Layers rather than clobbers: it only ever writes `exclusion_reason` where it
 * IS NULL, and only ever clears its OWN reason. A `vehicle_speed` exclusion is
 * never overwritten and never resurrected.
 */
function duplicateExclusionStatements(
  userId: string,
  localDate: string,
): { query: string; params: any[] }[] {
  const enabled = duplicateExclusionEnabled();
  return [
    {
      // Pass 1: recompute `duplicate_of` for the day, from scratch.
      // Unconditional — this column is an observation, not a policy, and the
      // review endpoints report on it even while the kill switch is off.
      query: `
	WITH day AS (
		SELECT
			w.workout_id,
			w.source_bundle_id,
			w.distance,
			w.created_at,
			w.device_end_date AS ends_at,
			w.device_end_date
				- (w.total_duration * interval '1 second') AS starts_at,
			w.total_duration,
			EXISTS (
				SELECT 1 FROM workout_routes r WHERE r.workout_id = w.workout_id
			) AS has_route,
			-- Is this row OLDER than the user's grandfather line, i.e. one that
			-- pass 3 is forbidden to exclude?
			(u.dedupe_since IS NOT NULL AND w.created_at < u.dedupe_since)
				AS grandfathered
		FROM workouts w
		JOIN users u ON u.user_id = w.user_id
		WHERE w.user_id = $1 AND w.local_date = $2::date
			AND w.deleted_at IS NULL
			AND w.source_bundle_id IS NOT NULL
			AND w.total_duration > 0
	),
	-- Preference order: the copy we'd rather keep sorts FIRST.
	--
	-- "grandfathered" leads deliberately. A row older than dedupe_since can
	-- never be excluded, so if it were the one designated as the duplicate the
	-- pair would BOTH keep counting — the exact double-count this whole pass
	-- exists to stop. Reachable as soon as history import exists: an imported
	-- workout is new (excludable) and carries a route, so on "has_route" alone
	-- it would win survivorship over the un-excludable native row it duplicates.
	-- Keeping the un-excludable row means the other side is always actionable.
	-- Route preference still decides within each grandfather class.
	ranked AS (
		SELECT *, ROW_NUMBER() OVER (
			ORDER BY grandfathered DESC, has_route DESC,
				created_at ASC, workout_id ASC
		) AS pref
		FROM day
	),
	-- Every ordered pair that describes one run recorded by two apps.
	-- NB: not named "overlaps" — that is the OVERLAPS operator keyword, which
	-- Postgres rejects as a CTE name.
	same_run AS (
		SELECT a.workout_id AS dup_id, b.workout_id AS keep_id, b.pref AS keep_pref
		FROM ranked a
		JOIN ranked b
			ON b.pref < a.pref
			AND a.source_bundle_id <> b.source_bundle_id
			AND EXTRACT(EPOCH FROM (
				LEAST(a.ends_at, b.ends_at) - GREATEST(a.starts_at, b.starts_at)
			)) >= $3 * LEAST(a.total_duration, b.total_duration)
			AND abs(a.distance - b.distance) <= GREATEST(
				$4, $5 * GREATEST(a.distance, b.distance)
			)
	),
	-- A row is a duplicate if any better-ranked row is the same run...
	dups AS (SELECT DISTINCT dup_id FROM same_run),
	-- ...and it may only point at a keeper, never at another duplicate, so a
	-- three-app chain collapses onto one survivor instead of a linked list.
	resolved AS (
		SELECT o.dup_id, o.keep_id,
			ROW_NUMBER() OVER (PARTITION BY o.dup_id ORDER BY o.keep_pref) AS rn
		FROM same_run o
		WHERE o.keep_id NOT IN (SELECT dup_id FROM dups)
	),
	final AS (SELECT dup_id, keep_id FROM resolved WHERE rn = 1)
	UPDATE workouts w
	SET duplicate_of = f.keep_id
	FROM (
		SELECT d.workout_id, f.keep_id
		FROM day d
		LEFT JOIN final f ON f.dup_id = d.workout_id
	) f(workout_id, keep_id)
	WHERE w.workout_id = f.workout_id AND w.user_id = $1
		-- Skip no-op rewrites: a re-sync of an unchanged day costs no row
		-- versions and no index churn (same rule as feed_role).
		AND w.duplicate_of IS DISTINCT FROM f.keep_id`,
      params: [
        userId,
        localDate,
        DUPLICATE_MIN_OVERLAP_RATIO,
        DUPLICATE_DISTANCE_FLOOR,
        DUPLICATE_DISTANCE_TOLERANCE,
      ],
    },
    {
      // Pass 2: release rows that are no longer duplicates — or every row we
      // ever excluded, when the kill switch is off, so flipping it off actually
      // unwinds. Only ever clears OUR reason; a speed exclusion is untouched.
      query: `
	UPDATE workouts SET exclusion_reason = NULL
	WHERE user_id = $1 AND local_date = $2::date
		AND exclusion_reason = '${DUPLICATE_EXCLUSION_REASON}'
		AND (NOT $3::boolean OR duplicate_of IS NULL)`,
      params: [userId, localDate, enabled],
    },
    {
      // Pass 3: exclude, but only past the user's grandfather line.
      //
      // `created_at >= dedupe_since` is what keeps this from rewriting history:
      // every workout uploaded before the feature shipped pre-dates the stamp,
      // so nobody's totals or streaks move when the switch goes on. A user who
      // explicitly asks to clean up their history has `dedupe_since` moved back
      // (POST /workouts/:userId/duplicates/resolve) and only then do old rows
      // qualify. A NULL stamp excludes nothing.
      query: `
	UPDATE workouts w
	SET exclusion_reason = '${DUPLICATE_EXCLUSION_REASON}'
	FROM users u
	WHERE w.user_id = $1 AND w.local_date = $2::date
		AND u.user_id = w.user_id
		AND $3::boolean
		AND w.duplicate_of IS NOT NULL
		AND w.exclusion_reason IS NULL
		AND w.deleted_at IS NULL
		AND u.dedupe_since IS NOT NULL
		AND w.created_at >= u.dedupe_since`,
      params: [userId, localDate, enabled],
    },
  ];
}

/** Re-run cross-app duplicate detection for one (user, local_date). */
export async function recomputeDuplicatesForDay(
  userId: string,
  localDate: string,
): Promise<void> {
  await db.transaction([
    advisoryLockStatement(userId),
    ...duplicateExclusionStatements(userId, localDate),
    ...feedRoleStatements(userId, localDate),
  ]);
}

export type DuplicateSummary = {
  /** Grandfathered duplicates: detected, but still counting toward totals. */
  pendingCount: number;
  /** Miles that would come off the user's totals if they clean these up. */
  pendingMiles: number;
  /** Days those duplicates fall on — what the cleanup would recompute. */
  affectedDays: number;
  /** Duplicates currently excluded (i.e. already not counting). */
  excludedCount: number;
  /** Apps involved, so the UI can say "Strava and Garmin Connect". */
  apps: string[];
  sample: {
    workoutId: string;
    localDate: string;
    distance: number;
    sourceBundleId: string | null;
    duplicateOf: string;
  }[];
};

/**
 * What cross-app duplicate detection found for a user, split into what is
 * already excluded and what is grandfathered (detected but still counting,
 * because it pre-dates their `dedupe_since`).
 *
 * This is the read behind the Connections screen's "we found N duplicates"
 * card. It never changes anything — the user decides.
 */
export async function getDuplicateSummary(
  userId: string,
): Promise<DuplicateSummary> {
  const rows = await db.query<{
    workout_id: string;
    local_date: string;
    distance: string | number;
    source_bundle_id: string | null;
    duplicate_of: string;
    is_excluded: boolean;
  }>(
    `SELECT w.workout_id, to_char(w.local_date, 'YYYY-MM-DD') AS local_date,
		w.distance, w.source_bundle_id, w.duplicate_of,
		(w.exclusion_reason = $2) AS is_excluded
	FROM workouts w
	WHERE w.user_id = $1
		AND w.duplicate_of IS NOT NULL
		AND w.deleted_at IS NULL
		AND (w.exclusion_reason IS NULL OR w.exclusion_reason = $2)
	ORDER BY w.local_date DESC, w.workout_id`,
    [userId, DUPLICATE_EXCLUSION_REASON],
  );

  const pending = rows.filter((r) => !r.is_excluded);
  const days = new Set(pending.map((r) => r.local_date));
  const apps = [
    ...new Set(
      rows.map((r) => r.source_bundle_id).filter((b): b is string => !!b),
    ),
  ];

  return {
    pendingCount: pending.length,
    pendingMiles:
      Math.round(
        pending.reduce((sum, r) => sum + Number(r.distance), 0) * 100,
      ) / 100,
    affectedDays: days.size,
    excludedCount: rows.length - pending.length,
    apps,
    sample: pending.slice(0, 25).map((r) => ({
      workoutId: r.workout_id,
      localDate: r.local_date,
      distance: Number(r.distance),
      sourceBundleId: r.source_bundle_id,
      duplicateOf: r.duplicate_of,
    })),
  };
}

/**
 * The user's explicit opt-in to clean up historical duplicates.
 *
 * Moves `dedupe_since` back past their whole history, then re-runs the pass on
 * exactly the days that hold duplicates (bounded — not their entire archive).
 * This is the ONLY thing that can change already-uploaded totals, and it only
 * ever runs because someone tapped the button; nothing here happens on a sync.
 *
 * Returns the days it touched so the caller can refresh derived state.
 */
export async function resolveDuplicateHistory(
  userId: string,
): Promise<{ days: string[]; removedMiles: number }> {
  const before = await getDuplicateSummary(userId);
  if (before.pendingCount === 0) return { days: [], removedMiles: 0 };

  const dayRows = await db.query<{ local_date: string }>(
    `SELECT DISTINCT to_char(local_date, 'YYYY-MM-DD') AS local_date
	FROM workouts
	WHERE user_id = $1 AND duplicate_of IS NOT NULL AND deleted_at IS NULL
		AND (exclusion_reason IS NULL OR exclusion_reason = $2)`,
    [userId, DUPLICATE_EXCLUSION_REASON],
  );

  await db.query(
    `UPDATE users SET dedupe_since = COALESCE(
		(SELECT MIN(created_at) FROM workouts WHERE user_id = $1), dedupe_since
	) WHERE user_id = $1`,
    [userId],
  );

  const days = dayRows.map((r) => r.local_date);
  for (const localDate of days) {
    await recomputeDuplicatesForDay(userId, localDate);
  }

  return { days, removedMiles: before.pendingMiles };
}

/**
 * Lock a user's workout rows for the duration of the caller's transaction.
 *
 * Two devices syncing at once (phone and Watch, or a client retrying an
 * in-flight upload) both recompute the same day. Under READ COMMITTED each
 * statement's window functions run against its own snapshot, and row-level
 * blocking re-checks the WHERE clause, not the value the subquery already
 * derived — so both can settle on a different row as 'daily_mile' and the mile
 * shows up twice in the feed. Serializing per user removes the interleaving.
 *
 * Locking per USER rather than per day is deliberate: a batch spanning several
 * days would otherwise take day locks in whatever order the payload arrived,
 * which is a deadlock waiting to happen.
 */
function advisoryLockStatement(userId: string) {
  return {
    query: `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`,
    params: [userId],
  };
}

/** Reclassify one (user, local_date) in its own transaction. */
export async function recomputeFeedRolesForDay(
  userId: string,
  localDate: string,
): Promise<void> {
  await db.transaction([
    advisoryLockStatement(userId),
    ...feedRoleStatements(userId, localDate),
  ]);
}

function dateStringMinus(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

/**
 * Today's date (YYYY-MM-DD) in the user's local timezone, derived from the
 * timezone_offset of their most recent workout (UTC if they have none).
 */
export async function getUserLocalToday(userId: string): Promise<string> {
  const todayResult = await db.query<{ user_today: string }>(
    `
    SELECT to_char(
      (NOW() + (COALESCE(
        (SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
        0
      ) || ' minutes')::interval)::date,
      'YYYY-MM-DD'
    ) AS user_today
  `,
    [userId],
  );
  return todayResult[0].user_today;
}

/**
 * All of a user's streak runs ("eras"), newest first, plus the longest length
 * seen in them. Delegates to streakFeatureCore so covered days count exactly
 * when getActiveStreak would count them.
 */
export async function getStreakErasForUser(
  userId: string,
): Promise<{ eras: StreakEra[]; longest: number }> {
  const userToday = await getUserLocalToday(userId);
  return computeStreakEras(userId, userToday);
}

export async function getActiveStreak(userId: string) {
  const userToday = await getUserLocalToday(userId);

  // Streak-features gate: enrolled users (new build + env switch on) walk the
  // coverage-aware path so token-covered days count. Everyone else falls
  // through to the UNTOUCHED legacy walk below — their output is byte-
  // identical to before this feature existed.
  if (await coverageActiveFor(userId)) {
    return computeCoveredStreak(userId, userToday);
  }

  const yesterday = dateStringMinus(userToday, 1);

  const qualifyingDaysQuery = `
    SELECT to_char(local_date, 'YYYY-MM-DD') AS local_date
    FROM workouts
    WHERE user_id = $1
    AND deleted_at IS NULL AND exclusion_reason IS NULL
    GROUP BY local_date
    HAVING SUM(distance) >= 0.95
    ORDER BY local_date DESC
    LIMIT $2 OFFSET $3
  `;

  const LIMIT = 100;
  let index = 0;
  let streak = 0;
  let streakStartDay: string | undefined;
  let expectedDate: string | undefined;

  while (true) {
    const results = await db.query(qualifyingDaysQuery, [
      userId,
      LIMIT,
      index * LIMIT,
    ]);
    if (results.length === 0) break;

    for (const row of results) {
      const date: string = row.local_date;

      if (expectedDate === undefined) {
        if (date !== userToday && date !== yesterday) {
          return { streak: 0, start: undefined };
        }
        streak = 1;
        streakStartDay = date;
        expectedDate = dateStringMinus(date, 1);
      } else if (date === expectedDate) {
        streak++;
        streakStartDay = date;
        expectedDate = dateStringMinus(date, 1);
      } else {
        return { streak, start: streakStartDay };
      }
    }

    index++;
  }

  return { streak, start: streakStartDay };
}

export async function getTotalMiles(userId: string, startDate?: string) {
  let distanceQuery = `
    SELECT SUM(distance) FROM workouts
    WHERE user_id = $1
    AND deleted_at IS NULL AND exclusion_reason IS NULL
    `;

  const params: (string | number)[] = [userId];

  if (startDate) {
    distanceQuery += ` AND local_date >= $2`;
    params.push(startDate);
  }

  return (await db.query(distanceQuery, params))[0]?.sum;
}

export async function getBestMilesDay(userId: string, startDate?: string) {
  let bestDayQuery = `
    SELECT local_date, SUM(distance) as total_distance FROM workouts
    WHERE user_id = $1
    AND deleted_at IS NULL AND exclusion_reason IS NULL
    `;

  const params: (string | number)[] = [userId];

  if (startDate) {
    bestDayQuery += ` AND local_date >= $2`;
    params.push(startDate);
  }

  bestDayQuery += `
    GROUP BY local_date
    ORDER BY total_distance DESC
    LIMIT 1
    `;

  return (await db.query(bestDayQuery, params))[0];
}

export async function getBestSplit(userId: string, startDate?: string) {
  let bestSplitQuery = `
    SELECT
      ws.split_pace AS best_split_time,
      w.*
    FROM workout_splits ws
    JOIN workouts w ON ws.workout_id = w.workout_id
    WHERE w.user_id = $1
	AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
	AND split_distance >= 0.95
	AND ws.split_pace >= ${MIN_PLAUSIBLE_MILE_SECONDS}
	`;

  const params: (string | number)[] = [userId];

  if (startDate) {
    bestSplitQuery += ` AND w.local_date >= $2`;
    params.push(startDate);
  }

  bestSplitQuery += `
    ORDER BY ws.split_pace ASC
    LIMIT 1
	`;

  const result = await db.query(bestSplitQuery, params);

  if (!result || result.length === 0) {
    return null;
  }

  const { best_split_time, ...workout } = result[0];

  return { best_split_time, workout };
}

/**
 * A user's recent workouts, newest first, each tagged with whether it carries a
 * GPS route and whether it has a real photo — so a friend's workout row can
 * show the same "Route"/"Photo" chips the owner sees on their own rows. Both
 * flags are ADDITIVE: older clients simply ignore them.
 *
 * Both flags obey `workout_visibility` (who may see this user's content at all)
 * AND, for routes, the author's "Share route maps" consent — an author who
 * turned either off must not even have the EXISTENCE of a route advertised to
 * others, only to themselves. `viewerId` is what makes "the owner always sees
 * their own" work; omit it and everyone is treated as a stranger (fail-closed).
 *
 * `has_photo` means a DELIBERATE photo (`is_auto = false`), never a generated
 * route/stats card — the same "real photo" test the feed uses. It reports mere
 * existence, never a url, so it reveals nothing `lockUnearnedPhotos` protects:
 * a gated viewer already sees a lock card on today's photo posts in the feed.
 *
 * The photo lookup is a per-user CTE rather than a correlated EXISTS per row:
 * `posts` has no plain `workout_id` index (only partial uniques that a
 * `is_auto = false` predicate can't use), so a subquery per row would seq-scan
 * `posts` once per workout. Keyed on user_id it rides `idx_posts_user_created`.
 *
 * Routes themselves are NOT shipped here — 50 polylines per page is a lot of
 * jsonb for a list that draws none of them. The detail screen pulls the one it
 * needs from `getWorkoutRoute`.
 */
export async function getRecentWorkouts(
  userId: string,
  limit: number | null = 10,
  viewerId?: string | null,
) {
  const recentWorkoutsQuery = `
	WITH recent AS (
		SELECT * FROM workouts
		WHERE user_id = $1
		AND deleted_at IS NULL
		-- The OWNER sees everything, including sub-floor accidents and workouts
		-- folded into a rollup — this is the list they delete bad entries from,
		-- and it already shows auto-excluded ones for the same reason. Visitors
		-- on someone else's profile get the same view as the feed.
		AND ($1 = $3 OR feed_role IN ('daily_mile', 'extra'))
		ORDER BY device_end_date DESC
		LIMIT $2
	),
	photo_workouts AS (
		SELECT DISTINCT workout_id
		FROM posts
		WHERE user_id = $1
		AND deleted_at IS NULL
		AND workout_id IN (SELECT workout_id FROM recent)
		AND is_auto = FALSE
		AND media_url <> ''
	),
	route_consent AS (
		SELECT (COALESCE(ns.share_route_maps, true) OR $1 = $3) AS allowed
		FROM users u
		LEFT JOIN notification_settings ns ON ns.user_id = u.user_id
		WHERE u.user_id = $1
	)
	SELECT r.*,
		-- COALESCE the WHOLE expression, not just its parts: with no viewer,
		-- '$1 = $3' is NULL and the visibility predicate evaluates to NULL
		-- rather than false, so 'true AND NULL' made these columns come back
		-- JSON null instead of a boolean. NULL is fail-closed in a WHERE but
		-- meaningless as a value — these must always be a real true/false.
		COALESCE(
			wr.workout_id IS NOT NULL
			AND COALESCE((SELECT allowed FROM route_consent), false)
			AND ${VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL("$1", "$3")},
			false
		) AS has_route,
		COALESCE(
			pw.workout_id IS NOT NULL
			AND ${VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL("$1", "$3")},
			false
		) AS has_photo,
		-- Restate a day's 'daily_mile' anchor with the whole day's rollup, exactly
		-- like every other read surface (getUnifiedFeed, getFriendsWorkoutFeed in
		-- friendshipService.ts). The anchor is the leg that CROSSED the mile and
		-- carries only its own distance, so a 0.95 mi day otherwise renders as its
		-- 0.20 mi final leg with the earlier legs hidden. These trailing columns
		-- intentionally shadow r.*'s raw values (node-pg keeps the last of a
		-- duplicate column name). The lateral is gated to visitors only, so the
		-- OWNER — who sees every individual leg in this same list — keeps raw
		-- per-workout numbers and it never reads as double-counting.
		COALESCE(roll.distance, r.distance) AS distance,
		COALESCE(roll.total_duration, r.total_duration) AS total_duration,
		COALESCE(roll.calories, r.calories) AS calories,
		COALESCE(roll.steps, r.steps) AS steps
	FROM recent r
	LEFT JOIN workout_routes wr ON wr.workout_id = r.workout_id
	LEFT JOIN photo_workouts pw ON pw.workout_id = r.workout_id
	LEFT JOIN LATERAL (
		SELECT
			SUM(m.distance)::float AS distance,
			SUM(m.total_duration)::float AS total_duration,
			SUM(m.calories)::float AS calories,
			SUM(m.steps)::int AS steps
		FROM workouts m
		WHERE r.feed_role = 'daily_mile'
			-- Visitors only: $1 (owner) is never null, so IS DISTINCT FROM is true
			-- for any other viewer AND for a null viewer (a fail-closed stranger
			-- still gets the feed-accurate number, matching the row filter above).
			AND $1 IS DISTINCT FROM $3
			AND m.user_id = r.user_id
			AND m.local_date = r.local_date
			AND m.deleted_at IS NULL AND m.exclusion_reason IS NULL
			AND (
				m.feed_role IN ('rolled_up', 'daily_mile')
				OR (m.feed_role = 'hidden' AND m.device_end_date <= r.device_end_date)
			)
	) roll ON TRUE
	ORDER BY r.device_end_date DESC
	`;

  return await db.query(recentWorkoutsQuery, [userId, limit, viewerId ?? null]);
}

/**
 * ONE workout's stored GPS trace, or null — what a workout DETAIL screen needs
 * to draw its map.
 *
 * The owner's own detail reads its route from HealthKit, which only ever holds
 * their own runs, so a friend's detail had no way to draw the map it was being
 * told existed. Two independent gates, BOTH required:
 *   1. `workout_visibility` — who may see this user's content at all.
 *      Authentication alone is NOT access: without this, any account
 *      (including one the owner blocked) could pull a stranger's polyline by
 *      guessing an id. Routes are the most sensitive thing here; they start at
 *      people's homes.
 *   2. `share_route_maps` — whether routes are part of what those people get.
 *      Owner exempt.
 * Deliberately per-workout — never the full-history dump `/routes` keeps
 * self-only.
 */
export async function getWorkoutRoute(
  userId: string,
  workoutId: string,
  viewerId: string,
): Promise<[number, number][] | null> {
  const rows = await db.query<{ route: [number, number][] | null }>(
    `SELECT wr.route
		 FROM workouts w
		 LEFT JOIN notification_settings ns ON ns.user_id = w.user_id
		 JOIN workout_routes wr ON wr.workout_id = w.workout_id
		 WHERE w.workout_id = $2
			 AND w.user_id = $1
			 AND w.deleted_at IS NULL
			 AND ${VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL("w.user_id", "$3")}
			 AND (COALESCE(ns.share_route_maps, true) OR w.user_id = $3)`,
    [userId, workoutId, viewerId],
  );
  return rows[0]?.route ?? null;
}

/**
 * Every stored GPS route for a user's live workouts, newest first — powers the
 * personal route heatmap (all paths overlaid on one map). Self-access only:
 * route sharing settings gate what FRIENDS see, but your own history is
 * always yours. Capped because routes are ~300 points each; 1000 routes
 * (~3 years of daily runs) is already several MB of JSON.
 */
export async function getUserRoutes(userId: string, limit: number = 1000) {
  return await db.query<{
    workout_id: string;
    local_date: string;
    workout_type: string;
    route: unknown;
  }>(
    `SELECT w.workout_id, w.local_date, w.workout_type, wr.route
		 FROM workout_routes wr
		 JOIN workouts w ON w.workout_id = wr.workout_id
		 WHERE w.user_id = $1 AND w.deleted_at IS NULL
		 ORDER BY w.device_end_date DESC
		 LIMIT $2`,
    [userId, limit],
  );
}

/**
 * Today's date ('YYYY-MM-DD') in the user's local timezone, derived from their
 * most recent workout's timezone_offset (matches workouts.local_date format).
 * Falls back to the server's UTC date if the user has no workouts.
 */
export async function getUserLocalDate(userId: string): Promise<string> {
  const rows = await db.query<{ local_date: string }>(
    `SELECT (NOW() + (COALESCE(
			(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
			0
		) || ' minutes')::interval)::date::text AS local_date`,
    [userId],
  );
  return rows[0].local_date;
}

/**
 * Canonical "daily mile done" tolerance, as a fraction of the goal. Streak
 * counting (leaderboardService), daily challenges, and the weekly recap all
 * treat >= 0.95 mi as a completed day (GPS under-measure allowance). Every
 * completion check against today's miles must apply this — a raw `>= 1.0`
 * check lets a 0.98-mile day extend the streak and display as "1.00 mi ·
 * 100%" (2-decimal rounding) while still reading "incomplete" for nudges,
 * friend notifications, and posting.
 */
export const DAILY_GOAL_TOLERANCE = 0.95;

export async function getTodayMiles(userId: string) {
  // Use the user's timezone offset from their most recent workout to determine
  // what "today" is in their local time (local_date is stored in user's timezone)
  const todayMilesQuery = `
	WITH user_tz AS (
		SELECT COALESCE(
			(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
			0
		) AS tz_offset
	)
	SELECT SUM(w.distance) as total_distance FROM workouts w, user_tz
	WHERE w.user_id = $1
	AND w.local_date = (NOW() + (user_tz.tz_offset || ' minutes')::interval)::date
	AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
	`;

  const result = await db.query(todayMilesQuery, [userId]);
  return result[0]?.total_distance || 0;
}

/**
 * Per-day mile totals for the user's last 7 LOCAL days (their "today" plus
 * the 6 before it, derived from their latest workout's timezone offset the
 * same way getTodayMiles does). Every day is present — zero-mile days
 * included — so clients can render a week without inferring gaps.
 *
 * This exists because profile "last 7 days" charts were being derived from
 * the capped recent-workouts LIST: a user logging several workouts a day
 * pushed the week's early days out of the cap and their chart showed empty
 * days mid-400-day-streak. Counting matches getTodayMiles exactly
 * (deleted_at IS NULL AND exclusion_reason IS NULL); feed_role is display-
 * only and must never gate a SUM.
 */
export async function getLast7DayMiles(
  userId: string,
): Promise<{ date: string; miles: number }[]> {
  const query = `
	WITH user_tz AS (
		SELECT COALESCE(
			(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
			0
		) AS tz_offset
	),
	days AS (
		SELECT ((NOW() + (user_tz.tz_offset || ' minutes')::interval)::date - offs.n) AS day
		FROM user_tz, generate_series(0, 6) AS offs(n)
	)
	SELECT to_char(d.day, 'YYYY-MM-DD') AS date,
		COALESCE(SUM(w.distance), 0) AS miles
	FROM days d
	LEFT JOIN workouts w
		ON w.user_id = $1
		AND w.local_date = d.day
		AND w.deleted_at IS NULL
		AND w.exclusion_reason IS NULL
	GROUP BY d.day
	ORDER BY d.day
	`;

  const rows = await db.query<{ date: string; miles: string | number | null }>(
    query,
    [userId],
  );
  return rows.map((r) => ({
    date: r.date,
    miles: r.miles == null ? 0 : Number(r.miles),
  }));
}

/**
 * Total miles a user logged on a specific local date (their timezone).
 * Used to validate "did they complete their mile that day?" for historical
 * events like an old mile-completion notification being hyped.
 */
export async function getMilesOnLocalDate(
  userId: string,
  localDate: string,
): Promise<number> {
  const result = await db.query<{ total_distance: string | number | null }>(
    `SELECT COALESCE(SUM(distance), 0) AS total_distance
		FROM workouts
		WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId, localDate],
  );
  const value = result[0]?.total_distance;
  return value == null ? 0 : Number(value);
}

export interface DailyGoalStatus {
  completed: boolean;
  miles: number;
  goalMiles: number;
  localDate: string;
}

/**
 * Whether the user has met their personal daily goal (goal_miles) today, in
 * their local timezone. This is the authoritative server-side gate for posting
 * a story/feed post — never trust a client-supplied "completed" flag.
 */
export async function getDailyGoalStatus(
  userId: string,
): Promise<DailyGoalStatus> {
  const localDate = await getUserLocalDate(userId);
  const [miles, goalRows] = await Promise.all([
    getMilesOnLocalDate(userId, localDate),
    db.query<{ goal_miles: string | number | null }>(
      `SELECT goal_miles FROM users WHERE user_id = $1`,
      [userId],
    ),
  ]);
  const goalMiles = Number(goalRows[0]?.goal_miles ?? 1);
  // Same tolerance as streaks/challenges — a day the streak counts as done
  // must also unlock posting.
  const completed = miles + 1e-9 >= goalMiles * DAILY_GOAL_TOLERANCE;
  return { completed, miles, goalMiles, localDate };
}

export interface TodayStats {
  miles: number;
  durationSeconds: number;
  bestSplitPaceSecMi: number | null;
}

/**
 * Aggregate today's workout stats for a user, using the user's local-date
 * predicate (same as getTodayMiles).
 *
 * bestSplitPaceSecMi: MIN split pace (sec/mi) across today's splits where
 * split_distance >= 0.95. Falls back to MIN(total_duration / distance) over
 * today's workouts with distance >= 0.95. NULL if neither is available.
 */
export async function getTodayStats(userId: string): Promise<TodayStats> {
  const query = `
	WITH user_tz AS (
		SELECT COALESCE(
			(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
			0
		) AS tz_offset
	),
	today_workouts AS (
		SELECT w.workout_id, w.distance, w.total_duration
		FROM workouts w, user_tz
		WHERE w.user_id = $1
			AND w.local_date = (NOW() + (user_tz.tz_offset || ' minutes')::interval)::date
			AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
	),
	totals AS (
		SELECT
			COALESCE(SUM(distance), 0) AS miles,
			COALESCE(SUM(total_duration), 0) AS duration_seconds
		FROM today_workouts
	),
	split_best AS (
		SELECT MIN(ws.split_pace) AS pace
		FROM today_workouts tw
		JOIN workout_splits ws ON ws.workout_id = tw.workout_id
		WHERE ws.split_distance >= 0.95 AND ws.split_pace >= ${MIN_PLAUSIBLE_MILE_SECONDS}
	),
	workout_best AS (
		SELECT MIN(total_duration / NULLIF(distance, 0)) AS pace
		FROM today_workouts
		WHERE distance >= 0.95
	)
	SELECT
		t.miles::float8 AS miles,
		t.duration_seconds::float8 AS duration_seconds,
		COALESCE(sb.pace, wb.pace) AS best_split_pace_sec_mi
	FROM totals t
	LEFT JOIN split_best sb ON TRUE
	LEFT JOIN workout_best wb ON TRUE
	`;

  const rows = await db.query<{
    miles: number | string;
    duration_seconds: number | string;
    best_split_pace_sec_mi: number | string | null;
  }>(query, [userId]);

  const row = rows[0];
  const toNum = (v: number | string | null | undefined): number =>
    v == null ? 0 : typeof v === "string" ? Number(v) : v;
  const pace = row?.best_split_pace_sec_mi;

  return {
    miles: toNum(row?.miles),
    durationSeconds: toNum(row?.duration_seconds),
    bestSplitPaceSecMi: pace == null ? null : Number(pace),
  };
}

// Shared normalization for the date-range aggregation queries below: clamp the
// range to calendar dates (default end = today) and map competition activity
// aliases (run/walk) onto stored workout_type values. ONE definition so the
// scoring sum, the per-type breakdown, and the single-user variant can never
// disagree on what counts.
function normalizeDateRange(
  startDate: string,
  endDate?: string,
): { start: string; end: string } {
  const todaysDate = new Date().toISOString().split("T")[0];
  return {
    start: new Date(startDate).toISOString().split("T")[0],
    end: endDate ? new Date(endDate).toISOString().split("T")[0] : todaysDate,
  };
}

function normalizeWorkoutTypes(
  workoutTypes?: ("running" | "walking")[],
): string[] {
  const typeMap: Record<string, "running" | "walking"> = {
    run: "running",
    walk: "walking",
    running: "running",
    walking: "walking",
  };
  return (workoutTypes ?? ["running", "walking"])
    .map((t) => typeMap[t])
    .filter(Boolean);
}

export async function getQuantityDateRange(
  userId: string,
  startDate: string,
  endDate?: string,
  workoutTypes?: ("running" | "walking")[],
) {
  let query = `
		SELECT
			TO_CHAR(local_date, 'YYYY-MM-DD') as local_date,
			SUM(distance) as total_distance
		FROM workouts
		WHERE user_id = $1
			AND local_date >= $2
			AND local_date <= $3
			AND workout_type = ANY($4::text[])
			AND deleted_at IS NULL AND exclusion_reason IS NULL
		GROUP BY local_date
		ORDER BY local_date ASC
	`;

  const { start, end } = normalizeDateRange(startDate, endDate);
  const normalizedTypes = normalizeWorkoutTypes(workoutTypes);

  return await db.query(query, [userId, start, end, normalizedTypes]);
}

/**
 * Batched variant of getQuantityDateRange — returns one row per (user_id, local_date)
 * for an entire set of users in a single query. Used by competitionService to score
 * all participants at once instead of looping per user.
 */
export async function getQuantityDateRangeBatch(
  userIds: string[],
  startDate: string,
  endDate?: string,
  workoutTypes?: ("running" | "walking")[],
): Promise<{ user_id: string; local_date: string; total_distance: number }[]> {
  if (userIds.length === 0) return [];

  const query = `
		SELECT
			user_id,
			TO_CHAR(local_date, 'YYYY-MM-DD') as local_date,
			SUM(distance) as total_distance
		FROM workouts
		WHERE user_id = ANY($1::text[])
			AND local_date >= $2
			AND local_date <= $3
			AND workout_type = ANY($4::text[])
			AND deleted_at IS NULL AND exclusion_reason IS NULL
		GROUP BY user_id, local_date
		ORDER BY user_id, local_date ASC
	`;

  const { start, end } = normalizeDateRange(startDate, endDate);
  const normalizedTypes = normalizeWorkoutTypes(workoutTypes);

  return await db.query(query, [userIds, start, end, normalizedTypes]);
}

/**
 * Per-day, per-workout-type distance + workout counts for a set of users —
 * powers the competition detail view's walk/run breakdown (stats panel,
 * calendar day detail). Same filters as getQuantityDateRangeBatch, but keeps
 * workout_type instead of collapsing it.
 */
export async function getActivityBreakdownBatch(
  userIds: string[],
  startDate: string,
  endDate?: string,
  workoutTypes?: ("running" | "walking")[],
): Promise<
  {
    user_id: string;
    local_date: string;
    workout_type: string;
    total_distance: number;
    workout_count: number;
  }[]
> {
  if (userIds.length === 0) return [];

  const query = `
		SELECT
			user_id,
			TO_CHAR(local_date, 'YYYY-MM-DD') as local_date,
			workout_type,
			SUM(distance) as total_distance,
			COUNT(*)::int as workout_count
		FROM workouts
		WHERE user_id = ANY($1::text[])
			AND local_date >= $2
			AND local_date <= $3
			AND workout_type = ANY($4::text[])
			AND deleted_at IS NULL AND exclusion_reason IS NULL
		GROUP BY user_id, local_date, workout_type
		ORDER BY user_id, local_date ASC
	`;

  const { start, end } = normalizeDateRange(startDate, endDate);
  const normalizedTypes = normalizeWorkoutTypes(workoutTypes);

  return await db.query(query, [userIds, start, end, normalizedTypes]);
}

/**
 * Batched manual-workout check for a set of users over a date range.
 * Returns the set of user_ids that have at least one manual/edited workout in range.
 */
export async function getUsersWithManualWorkouts(
  userIds: string[],
  startDate: string,
  endDate: string,
): Promise<Set<string>> {
  if (userIds.length === 0) return new Set();

  const result = await db.query<{ user_id: string }>(
    `SELECT DISTINCT user_id FROM workouts
		 WHERE user_id = ANY($1::text[])
			AND local_date >= $2
			AND local_date <= $3
			AND source IN ('manual', 'edited')
			AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userIds, startDate, endDate],
  );

  return new Set(result.map((r) => r.user_id));
}

export async function updateWorkout(
  userId: string,
  workoutId: string,
  updates: { distance?: number; totalDuration?: number; workoutType?: string },
) {
  const current = await db.query(
    "SELECT distance, total_duration, original_distance FROM workouts WHERE workout_id = $1 AND user_id = $2",
    [workoutId, userId],
  );

  if (!current || current.length === 0) {
    return null;
  }

  const row = current[0];

  const result = await db.query(
    `UPDATE workouts SET
			distance = COALESCE($3, distance),
			total_duration = COALESCE($4, total_duration),
			workout_type = COALESCE($5, workout_type),
			source = 'edited',
			original_distance = COALESCE(original_distance, $6),
			original_duration = COALESCE(original_duration, $7)
		WHERE workout_id = $1 AND user_id = $2
		RETURNING *`,
    [
      workoutId,
      userId,
      updates.distance ?? null,
      updates.totalDuration ?? null,
      updates.workoutType ?? null,
      row.distance,
      row.total_duration,
    ],
  );

  // An edit can push a workout over or under the feed floor, or move the day
  // across the mile — either reshapes the whole day's roles.
  if (result[0]) {
    await recomputeFeedRolesForDay(userId, result[0].local_date);
  }

  return result[0];
}

/**
 * Returns the user's two tracked personal records computed from workouts,
 * optionally excluding a set of workout IDs (used to compute the "pre-upload"
 * baseline so the caller can detect a PR set by this upload).
 *
 * - fastestSplitPaceSecMi: MIN(split_pace) across qualifying splits (>=0.95mi, >0 pace).
 *   0 if the user has no qualifying splits.
 * - mostMilesInOneDay: MAX(SUM(distance) GROUP BY local_date). 0 if no workouts.
 * - fastestSplitDate / bestDayDate: local_date (YYYY-MM-DD) that set each record,
 *   null when there is no record. Ties resolve to the most recent date.
 */
export async function computePersonalRecords(
  userId: string,
  excludeWorkoutIds: string[] = [],
): Promise<{
  fastestSplitPaceSecMi: number;
  mostMilesInOneDay: number;
  fastestSplitDate: string | null;
  bestDayDate: string | null;
}> {
  const exclude = excludeWorkoutIds.length > 0;
  const excludeClause = exclude
    ? `AND NOT (w.workout_id = ANY($2::text[]))`
    : "";

  const paceQuery = `SELECT s.split_pace::text AS min_pace,
	       to_char(w.local_date, 'YYYY-MM-DD') AS pace_date
	   FROM workout_splits s
	   JOIN workouts w ON w.workout_id = s.workout_id
	   WHERE w.user_id = $1
	       AND s.split_pace >= ${MIN_PLAUSIBLE_MILE_SECONDS}
	       AND s.split_distance >= 0.95
	       ${excludeClause}
	   ORDER BY s.split_pace ASC, w.local_date DESC
	   LIMIT 1`;

  const dayQuery = `SELECT SUM(w.distance)::text AS best_day,
	       to_char(w.local_date, 'YYYY-MM-DD') AS best_day_date
	   FROM workouts w
	   WHERE w.user_id = $1 ${excludeClause}
	       AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
	   GROUP BY w.local_date
	   ORDER BY SUM(w.distance) DESC, w.local_date DESC
	   LIMIT 1`;

  const params: any[] = exclude ? [userId, excludeWorkoutIds] : [userId];

  const [paceRow, bestDayRow] = await Promise.all([
    db.query<{ min_pace: string | null; pace_date: string | null }>(
      paceQuery,
      params,
    ),
    db.query<{ best_day: string | null; best_day_date: string | null }>(
      dayQuery,
      params,
    ),
  ]);

  const fastestSplitPaceSecMi = paceRow[0]?.min_pace
    ? parseFloat(paceRow[0].min_pace)
    : 0;
  const mostMilesInOneDay = parseFloat(bestDayRow[0]?.best_day ?? "0") || 0;
  return {
    fastestSplitPaceSecMi,
    mostMilesInOneDay,
    fastestSplitDate: paceRow[0]?.pace_date ?? null,
    bestDayDate: bestDayRow[0]?.best_day_date ?? null,
  };
}

/**
 * Standard race distances tracked for personal records, in miles. A workout
 * sets the PR for the distance whose band its TOTAL distance falls in.
 * ponytail: whole-workout match (not best-effort segments inside longer runs).
 * The bands don't overlap, so a workout matches at most one distance. Only
 * running/walking workouts ever reach the workouts table, so no activity-type
 * filter is needed — the exclusion_reason/deleted_at guards (same as daily-mile
 * counting) keep out flagged/deleted rows. Widen RACE_BAND_LO/HI if real GPS
 * runs routinely miss their bucket.
 */
export const RACE_DISTANCES = [
  { key: "1mi", miles: 1 },
  { key: "2mi", miles: 2 },
  { key: "5k", miles: 3.106856 },
  { key: "5mi", miles: 5 },
  { key: "10k", miles: 6.213712 },
  { key: "15k", miles: 9.320568 },
  { key: "half", miles: 13.109375 },
  { key: "marathon", miles: 26.21875 },
] as const;

export type RaceDistanceKey = (typeof RACE_DISTANCES)[number]["key"];

const RACE_BAND_LO = 0.98;
const RACE_BAND_HI = 1.1;

// SQL CASE mapping workouts.distance -> race bucket key (NULL if it fits none).
// Built once from RACE_DISTANCES so bands stay DRY with the constant above.
const RACE_BUCKET_CASE = `CASE ${RACE_DISTANCES.map(
  (d) =>
    `WHEN w.distance BETWEEN ${d.miles * RACE_BAND_LO} AND ${d.miles * RACE_BAND_HI} THEN '${d.key}'`,
).join(" ")} END`;

export interface RaceRecord {
  distanceKey: RaceDistanceKey;
  durationSec: number;
  distanceMiles: number;
  workoutId: string;
  achievedDate: string; // YYYY-MM-DD in the user's local timezone
}

function mapRaceRow(r: {
  bucket: RaceDistanceKey;
  duration: string;
  distance: string;
  workout_id: string;
  achieved_date: string;
}): RaceRecord {
  return {
    distanceKey: r.bucket,
    durationSec: parseFloat(r.duration),
    distanceMiles: parseFloat(r.distance),
    workoutId: r.workout_id,
    achievedDate: r.achieved_date,
  };
}

/**
 * Fastest (MIN total_duration) qualifying workout per race distance, derived
 * live from the workouts table — there is no stored PR table, so a user's whole
 * history counts with zero migration/backfill. Optionally excludes a set of
 * workout IDs to compute a "pre-upload" baseline for same-day PR detection
 * (mirrors computePersonalRecords).
 * ponytail: full scan of the user's run/walk workouts per call; indexed on
 * user_id, hundreds–low-thousands of rows = ms. Add a cached table only if a
 * profiler says this is hot.
 */
export async function computeRaceRecords(
  userId: string,
  excludeWorkoutIds: string[] = [],
): Promise<RaceRecord[]> {
  const exclude = excludeWorkoutIds.length > 0;
  const excludeClause = exclude
    ? `AND NOT (w.workout_id = ANY($2::text[]))`
    : "";
  const query = `
    SELECT DISTINCT ON (bucket)
      bucket,
      total_duration::text AS duration,
      distance::text AS distance,
      workout_id,
      to_char(local_date, 'YYYY-MM-DD') AS achieved_date
    FROM (
      SELECT w.workout_id, w.total_duration, w.distance, w.local_date,
             ${RACE_BUCKET_CASE} AS bucket
      FROM workouts w
      WHERE w.user_id = $1
        AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
        AND w.total_duration > 0
        ${excludeClause}
    ) b
    WHERE bucket IS NOT NULL
    ORDER BY bucket, total_duration ASC, local_date DESC`;
  const params: any[] = exclude ? [userId, excludeWorkoutIds] : [userId];
  const rows = await db.query<{
    bucket: RaceDistanceKey;
    duration: string;
    distance: string;
    workout_id: string;
    achieved_date: string;
  }>(query, params);
  return rows.map(mapRaceRow);
}

/**
 * Every qualifying workout for ONE race distance, newest first — the user's
 * progression history for that distance. Same band logic as computeRaceRecords,
 * single bucket, no aggregate.
 */
export async function getRaceHistory(
  userId: string,
  distanceKey: RaceDistanceKey,
): Promise<RaceRecord[]> {
  const dist = RACE_DISTANCES.find((d) => d.key === distanceKey);
  if (!dist) return [];
  const rows = await db.query<{
    duration: string;
    distance: string;
    workout_id: string;
    achieved_date: string;
  }>(
    `SELECT total_duration::text AS duration,
            distance::text AS distance,
            workout_id,
            to_char(local_date, 'YYYY-MM-DD') AS achieved_date
       FROM workouts w
      WHERE w.user_id = $1
        AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
        AND w.total_duration > 0
        AND w.distance BETWEEN $2 AND $3
      ORDER BY w.device_end_date DESC`,
    [userId, dist.miles * RACE_BAND_LO, dist.miles * RACE_BAND_HI],
  );
  return rows.map((r) => mapRaceRow({ ...r, bucket: distanceKey }));
}
