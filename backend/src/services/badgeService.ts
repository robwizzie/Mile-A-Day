import { PostgresService } from "./DbService.js";
import { MIN_PLAUSIBLE_MILE_SECONDS, countedWorkoutSql } from "./mileTime.js";
import {
  DAILY_GOAL_TOLERANCE,
  getStreakErasForUser,
} from "./workoutService.js";
import {
  HOLIDAYS,
  holidayBadgeId,
  holidayDatesBetween,
  holidayKeyForLocalDate,
  holidayKeyFromBadgeId,
  type HolidayKey,
} from "./holidays.js";
import type {
  Badge,
  UserBadge,
  UserAggregates,
  RewardEvaluationResult,
  BadgeCategory,
} from "../types/badge.js";
import { evaluateChallengesForBatch } from "./dailyChallengeService.js";
import { evaluateWeeklyChallengeForUser } from "./weeklyChallengeService.js";

const db = PostgresService.getInstance();

// ─── Catalog reads ──────────────────────────────────────────────────

export async function getCatalog(): Promise<Badge[]> {
  const rows = await db.query<any>(
    `SELECT badge_id, category, name, description, icon, rarity, requirement, is_hidden, sort_order
		FROM badges
		ORDER BY sort_order ASC`,
  );
  return rows.map(rowToBadge);
}

export async function getUserBadges(userId: string): Promise<UserBadge[]> {
  const rows = await db.query<any>(
    `SELECT
			ub.badge_id, ub.earned_at, ub.is_new, ub.pin_slot, ub.triggering_workout_id, ub.progress_snapshot,
			b.category, b.name, b.description, b.icon, b.rarity, b.requirement, b.is_hidden
		FROM user_badges ub
		JOIN badges b ON b.badge_id = ub.badge_id
		WHERE ub.user_id = $1
		ORDER BY ub.earned_at DESC`,
    [userId],
  );
  return rows.map(rowToUserBadge);
}

const MAX_PINNED_BADGES = 3;

export async function setPinnedBadges(
  userId: string,
  badgeIds: string[],
): Promise<UserBadge[]> {
  const ids = badgeIds.slice(0, MAX_PINNED_BADGES);

  if (ids.length > 0) {
    const earnedRows = await db.query<{ badge_id: string }>(
      `SELECT badge_id FROM user_badges WHERE user_id = $1 AND badge_id = ANY($2::text[])`,
      [userId, ids],
    );
    const earnedSet = new Set(earnedRows.map((r) => r.badge_id));
    const missing = ids.filter((id) => !earnedSet.has(id));
    if (missing.length > 0) {
      throw new BadgePinError(
        `Cannot pin un-earned badge(s): ${missing.join(", ")}`,
      );
    }
  }

  const queries = [
    {
      query: `UPDATE user_badges SET pin_slot = NULL WHERE user_id = $1 AND pin_slot IS NOT NULL`,
      params: [userId],
    },
    ...ids.map((badgeId, slot) => ({
      query: `UPDATE user_badges SET pin_slot = $3 WHERE user_id = $1 AND badge_id = $2`,
      params: [userId, badgeId, slot],
    })),
  ];
  await db.transaction(queries);

  return getUserBadges(userId);
}

export class BadgePinError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "BadgePinError";
  }
}

export async function markBadgesViewed(userId: string): Promise<number> {
  const rows = await db.query<{ id: number }>(
    `UPDATE user_badges SET is_new = FALSE WHERE user_id = $1 AND is_new = TRUE RETURNING id`,
    [userId],
  );
  return rows.length;
}

// ─── Aggregate computation ──────────────────────────────────────────

/**
 * Everything the aggregate predicates read, over the user's WHOLE history —
 * which is what makes every medal retroactive: an upload, a social action, a
 * Recalibrate and the retro sweep all ask the same question ("has this person
 * EVER done X?"), never "is X true right now?". Workout-derived figures go
 * through countedWorkoutSql exactly like the totals the app shows.
 */
export async function computeAggregates(
  userId: string,
): Promise<UserAggregates> {
  const [streaks, totalsRow, paceRow, bestDayRow, ccRow] = await Promise.all([
    computeStreakAggregates(userId),
    db.query<{ total_miles: string | null }>(
      `SELECT COALESCE(SUM(w.distance),0)::text AS total_miles FROM workouts w WHERE w.user_id = $1 AND ${countedWorkoutSql("w")}`,
      [userId],
    ),
    db.query<{ min_pace: string | null }>(
      `SELECT MIN(s.split_pace)::text AS min_pace
			FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
			WHERE w.user_id = $1 AND s.split_pace >= ${MIN_PLAUSIBLE_MILE_SECONDS} AND s.split_distance >= 0.95 AND ${countedWorkoutSql("w")}`,
      [userId],
    ),
    db.query<{ best_day: string | null }>(
      `SELECT COALESCE(MAX(day_total),0)::text AS best_day FROM (
				SELECT SUM(w.distance) AS day_total FROM workouts w WHERE w.user_id = $1 AND ${countedWorkoutSql("w")} GROUP BY w.local_date
			) t`,
      [userId],
    ),
    db.query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM user_challenge_completions WHERE user_id = $1`,
      [userId],
    ),
  ]);

  const [socialRow] = await Promise.all([computeSocialAggregates(userId)]);

  const minPaceSeconds = paceRow[0]?.min_pace
    ? parseFloat(paceRow[0].min_pace)
    : 0;
  return {
    currentStreak: streaks.current,
    longestStreak: streaks.longest,
    totalMiles: parseFloat(totalsRow[0]?.total_miles ?? "0") || 0,
    fastestSplitPaceMinMi: minPaceSeconds > 0 ? minPaceSeconds / 60.0 : 0,
    mostMilesInOneDay: parseFloat(bestDayRow[0]?.best_day ?? "0") || 0,
    challengeCompletionsCount: parseInt(ccRow[0]?.count ?? "0", 10) || 0,
    ...socialRow,
  };
}

/**
 * Counts that back the social / app-function badges. Each is independent and
 * tolerant of the underlying tables not existing yet (returns 0) so badge
 * evaluation never breaks if a migration hasn't run.
 */
async function computeSocialAggregates(userId: string): Promise<{
  storyPostsCount: number;
  hypesGivenCount: number;
  nudgesSentCount: number;
  competitionsStarted: number;
  competitionsEntered: number;
  competitionsWon: number;
  buddySessionsCompleted: number;
  buddyDistinctPartners: number;
  buddySessionsWon: number;
  ghostsBeaten: number;
  bestGhostMargin: number;
  weeklyChallengesCompleted: number;
  bestWeeklyChallengeStreak: number;
}> {
  const zero = {
    storyPostsCount: 0,
    hypesGivenCount: 0,
    nudgesSentCount: 0,
    competitionsStarted: 0,
    competitionsEntered: 0,
    competitionsWon: 0,
    buddySessionsCompleted: 0,
    buddyDistinctPartners: 0,
    buddySessionsWon: 0,
    ghostsBeaten: 0,
    bestGhostMargin: 0,
    weeklyChallengesCompleted: 0,
    bestWeeklyChallengeStreak: 0,
  };
  try {
    const [
      stories,
      hypes,
      nudges,
      started,
      entered,
      won,
      buddyDone,
      buddyPartners,
      buddyWon,
      ghosts,
      weekly,
    ] = await Promise.all([
      db
        .query<{
          count: string;
        }>(
          `SELECT COUNT(*)::text AS count FROM posts WHERE user_id = $1 AND share_to_story = true`,
          [userId],
        )
        .catch(() => [{ count: "0" }]),
      db
        .query<{
          count: string;
        }>(
          // Self-hypes are allowed but never earn (hypeController skips the
          // evaluation for them) — so an all-history recount must skip them
          // too, or Recalibrate would award what the live path refuses.
          `SELECT COUNT(*)::text AS count FROM hype_log WHERE sender_id = $1 AND target_id <> sender_id`,
          [userId],
        )
        .catch(() => [{ count: "0" }]),
      // Nudges sent — both friend nudges and competition nudges promote the
      // same social behavior, so a "nudge" is counted from both. The LOGS are
      // pruned after 7 days (cleanupNotificationLogs), so counting them made
      // the nudge medals mean "N nudges this week" and no recount could ever
      // see further back. `users.nudges_sent_total` is the lifetime counter
      // (bumped by logNudge/logFriendNudge in the same statement as the log
      // row; seeded from the logs by its migration); GREATEST keeps the log
      // count as a floor for anything the counter predates.
      db
        .query<{
          count: string;
        }>(
          `SELECT GREATEST(
            (SELECT COALESCE(MAX(nudges_sent_total), 0) FROM users WHERE user_id = $1),
            (SELECT COUNT(*) FROM friend_nudge_log WHERE sender_id = $1)
            + (SELECT COUNT(*) FROM nudge_log WHERE sender_id = $1)
          )::text AS count`,
          [userId],
        )
        .catch(() => [{ count: "0" }]),
      db
        .query<{
          count: string;
        }>(
          `SELECT COUNT(*)::text AS count FROM competitions WHERE owner = $1`,
          [userId],
        )
        .catch(() => [{ count: "0" }]),
      db
        .query<{
          count: string;
        }>(
          `SELECT COUNT(*)::text AS count FROM competition_users WHERE user_id = $1 AND invite_status = 'accepted'`,
          [userId],
        )
        .catch(() => [{ count: "0" }]),
      db
        .query<{
          count: string;
        }>(
          `SELECT COUNT(*)::text AS count FROM competitions WHERE winner = $1`,
          [userId],
        )
        .catch(() => [{ count: "0" }]),
      // Buddy Walks. Only sessions that actually COMPLETED count — an
      // abandoned lobby or a walk someone bailed on isn't an achievement.
      db
        .query<{
          count: string;
        }>(
          `SELECT COUNT(*)::text AS count
             FROM buddy_session_participants p
             JOIN buddy_sessions s ON s.id = p.session_id
            WHERE p.user_id = $1 AND p.status = 'finished'
              AND s.status = 'completed'`,
          [userId],
        )
        .catch(() => [{ count: "0" }]),
      // Distinct PEOPLE walked with, across all completed sessions. Counting
      // sessions here would let one friend unlock the whole crew family.
      db
        .query<{
          count: string;
        }>(
          `SELECT COUNT(DISTINCT other.user_id)::text AS count
             FROM buddy_session_participants mine
             JOIN buddy_sessions s ON s.id = mine.session_id
             JOIN buddy_session_participants other
               ON other.session_id = mine.session_id
              AND other.user_id <> mine.user_id
            WHERE mine.user_id = $1 AND mine.status = 'finished'
              AND s.status = 'completed'
              AND other.status = 'finished'`,
          [userId],
        )
        .catch(() => [{ count: "0" }]),
      db
        .query<{
          count: string;
        }>(
          `SELECT COUNT(*)::text AS count FROM buddy_sessions WHERE winner_user_id = $1`,
          [userId],
        )
        .catch(() => [{ count: "0" }]),
      // Ghost races WON. `ghost_margin_seconds` is signed — every completed
      // race is stored, losses included — so this must compare, not just test
      // for presence. The MAX matters as much as the count: without `> 0` a
      // user who has only ever lost would report a negative "best margin".
      db
        .query<{
          count: string;
          best: string | null;
        }>(
          `SELECT COUNT(*)::text AS count,
                  COALESCE(MAX(ghost_margin_seconds), 0)::text AS best
             FROM workouts
            WHERE user_id = $1
              AND deleted_at IS NULL
              AND ghost_margin_seconds > 0`,
          [userId],
        )
        .catch(() => [{ count: "0", best: "0" }]),
      // Weekly challenges completed, and the longest run of consecutive weeks.
      // Gaps and islands over week_start: an ASC walk pairs with (d - rn * 7),
      // the reverse pairing silently returns 1 for every real streak.
      db
        .query<{
          count: string;
          best: string | null;
        }>(
          `WITH weeks AS (
             SELECT week_start FROM user_weekly_challenge_completions WHERE user_id = $1
           ),
           islands AS (
             SELECT week_start,
                    week_start - (ROW_NUMBER() OVER (ORDER BY week_start ASC) * 7)::int AS island
             FROM weeks
           ),
           runs AS (SELECT COUNT(*) AS run FROM islands GROUP BY island)
           SELECT
             (SELECT COUNT(*) FROM weeks)::text AS count,
             COALESCE((SELECT MAX(run) FROM runs), 0)::text AS best`,
          [userId],
        )
        .catch(() => [{ count: "0", best: "0" }]),
    ]);
    return {
      storyPostsCount: parseInt(stories[0]?.count ?? "0", 10) || 0,
      hypesGivenCount: parseInt(hypes[0]?.count ?? "0", 10) || 0,
      nudgesSentCount: parseInt(nudges[0]?.count ?? "0", 10) || 0,
      competitionsStarted: parseInt(started[0]?.count ?? "0", 10) || 0,
      competitionsEntered: parseInt(entered[0]?.count ?? "0", 10) || 0,
      competitionsWon: parseInt(won[0]?.count ?? "0", 10) || 0,
      buddySessionsCompleted: parseInt(buddyDone[0]?.count ?? "0", 10) || 0,
      buddyDistinctPartners: parseInt(buddyPartners[0]?.count ?? "0", 10) || 0,
      buddySessionsWon: parseInt(buddyWon[0]?.count ?? "0", 10) || 0,
      ghostsBeaten: parseInt(ghosts[0]?.count ?? "0", 10) || 0,
      bestGhostMargin: Math.floor(Number(ghosts[0]?.best ?? 0)) || 0,
      weeklyChallengesCompleted: parseInt(weekly[0]?.count ?? "0", 10) || 0,
      bestWeeklyChallengeStreak: parseInt(weekly[0]?.best ?? "0", 10) || 0,
    };
  } catch {
    return zero;
  }
}

/**
 * The user's streak runs from the ONE era computation the app itself shows
 * (streakFeatureCore.computeStreakEras via getStreakErasForUser — the Hall of
 * Streaks): qualified days plus token-covered days for enrolled users, pauses
 * bridged. `current` is the newest run (whether or not it still reaches
 * today — the old trailing-run semantics), `longest` the best run ever.
 *
 * Streak medals are judged on `longest`: a medal says "you reached N days",
 * and that stays true after the streak breaks. They used to read the CURRENT
 * run only, so a 400-day streak that broke before the medal was evaluated (or
 * whose workouts reached the server late) could never hold streak_365. It is
 * also what revocation measures, so the award and the revoke can never
 * disagree about the same history.
 */
async function computeStreakAggregates(
  userId: string,
): Promise<{ current: number; longest: number }> {
  const { eras, longest } = await getStreakErasForUser(userId);
  const current = eras[0]?.length ?? 0;
  return { current, longest: Math.max(longest, current) };
}

// ─── Evaluator ──────────────────────────────────────────────────────

export async function evaluateForUser(
  userId: string,
  newWorkoutIds: string[],
  opts: {
    /**
     * Judge holiday medals over the WHOLE history instead of only the days
     * this upload touched (Recalibrate + the retro sweep). Every other
     * category is all-history already.
     */
    allHolidays?: boolean;
    /** Stamped into progress_snapshot.source so an award is traceable. */
    source?: "recalibrate" | "retro_sweep";
  } = {},
): Promise<{ newlyEarnedBadges: UserBadge[] }> {
  const [aggregates, catalog, earned] = await Promise.all([
    computeAggregates(userId),
    getCatalog(),
    getEarnedBadgeIds(userId),
  ]);

  const triggeringWorkoutId = newWorkoutIds[newWorkoutIds.length - 1] ?? null;
  const snapshot = {
    streak: aggregates.currentStreak,
    longestStreak: aggregates.longestStreak,
    totalMiles: roundTo(aggregates.totalMiles, 2),
    fastestMilePace: roundTo(aggregates.fastestSplitPaceMinMi, 3),
    mostMilesInOneDay: roundTo(aggregates.mostMilesInOneDay, 2),
    challengeCompletions: aggregates.challengeCompletionsCount,
    ...(opts.source ? { source: opts.source } : {}),
  };

  const toInsert: {
    badgeId: string;
    aggregateOnly: boolean;
    workoutId?: string;
  }[] = [];

  for (const badge of catalog) {
    if (earned.has(badge.badgeId)) continue;
    const result = evaluatePredicate(badge, aggregates);
    if (result.earned) {
      toInsert.push({
        badgeId: badge.badgeId,
        aggregateOnly: result.aggregateOnly,
      });
    }
  }

  // Holiday medals are a fact about ONE DAY, not about aggregates, so they're
  // judged from the days this upload touched. Each is attributed to a workout
  // of THAT day, which is what keeps the controller's 24h push gate honest: a
  // backdated/first-run import of last Halloween earns the medal silently.
  const catalogIds = new Set(catalog.map((b) => b.badgeId));
  const holidayHits = opts.allHolidays
    ? await holidayHitsAllHistory(userId)
    : await evaluateHolidayBadges(userId, newWorkoutIds);
  for (const hit of holidayHits) {
    const badgeId = holidayBadgeId(hit.key);
    if (earned.has(badgeId) || !catalogIds.has(badgeId)) continue;
    toInsert.push({ badgeId, aggregateOnly: false, workoutId: hit.workoutId });
  }

  if (toInsert.length === 0) {
    return { newlyEarnedBadges: [] };
  }

  // ONE statement, and it reports only the rows IT wrote: an upload racing a
  // Recalibrate (or the retro sweep) can insert the same medal a moment
  // earlier, and a medal reported by both would be pushed twice.
  const inserted = await db.query<{ badge_id: string }>(
    `INSERT INTO user_badges (user_id, badge_id, triggering_workout_id, progress_snapshot)
		SELECT $1::text, t.badge_id, t.workout_id, $4::jsonb
		FROM unnest($2::text[], $3::text[]) AS t(badge_id, workout_id)
		ON CONFLICT (user_id, badge_id) DO NOTHING
		RETURNING badge_id`,
    [
      userId,
      toInsert.map((t) => t.badgeId),
      toInsert.map(
        (t) => t.workoutId ?? (t.aggregateOnly ? null : triggeringWorkoutId),
      ),
      JSON.stringify(snapshot),
    ],
  );
  if (inserted.length === 0) return { newlyEarnedBadges: [] };

  const insertedIds = inserted.map((r) => r.badge_id);
  const newlyEarnedBadges = await db.query<any>(
    `SELECT
			ub.badge_id, ub.earned_at, ub.is_new, ub.pin_slot, ub.triggering_workout_id, ub.progress_snapshot,
			b.category, b.name, b.description, b.icon, b.rarity, b.requirement, b.is_hidden
		FROM user_badges ub
		JOIN badges b ON b.badge_id = ub.badge_id
		WHERE ub.user_id = $1 AND ub.badge_id = ANY($2::text[])
		ORDER BY ub.earned_at DESC`,
    [userId, insertedIds],
  );

  return { newlyEarnedBadges: newlyEarnedBadges.map(rowToUserBadge) };
}

async function getEarnedBadgeIds(userId: string): Promise<Set<string>> {
  const rows = await db.query<{ badge_id: string }>(
    `SELECT badge_id FROM user_badges WHERE user_id = $1`,
    [userId],
  );
  return new Set(rows.map((r) => r.badge_id));
}

// ─── Holiday medals ─────────────────────────────────────────────────

/**
 * The goal line for a holiday day, shared by the sync-time award, the
 * revocation and the backfill (db/backfillHolidayMedals.ts) so the three can
 * never disagree: the day's COUNTED miles (callers filter with
 * countedWorkoutSql — a Strava twin or a vehicle-speed drive never counts)
 * reach the user's goal × the streak tolerance. The goal is clamped > 0:
 * `x >= 0 * 0.95` is vacuously true. `u` is the users row, the aggregate is
 * over `w`. It is the user's CURRENT goal — goal history isn't stored.
 */
export function holidayDayQualifiesSql(u: string, w: string): string {
  return `SUM(${w}.distance) >= (CASE WHEN ${u}.goal_miles > 0 THEN ${u}.goal_miles ELSE 1 END)::double precision * ${DAILY_GOAL_TOLERANCE}`;
}

/**
 * Every holiday date the product could have seen a walk on: from well before
 * the app existed through next year (a device a day ahead of UTC on Dec 31).
 * ~300 dates; the probe is `local_date = ANY(…)` over ONE user's rows.
 */
export function holidayProbeDates(): Array<{ date: string; key: HolidayKey }> {
  return holidayDatesBetween(2015, new Date().getUTCFullYear() + 1);
}

/**
 * Holidays this upload completed the goal on. Looks only at the local days
 * the given workouts belong to — never the whole history (that is the
 * backfill's job, once) — and returns, per holiday, the newest uploaded
 * counted workout of a qualifying day as the medal's trigger.
 */
async function evaluateHolidayBadges(
  userId: string,
  workoutIds: string[],
): Promise<Array<{ key: HolidayKey; workoutId: string }>> {
  if (workoutIds.length === 0) return [];
  const rows = await db.query<{ workout_id: string; local_date: string }>(
    `SELECT w.workout_id, to_char(w.local_date, 'YYYY-MM-DD') AS local_date
		FROM workouts w
		WHERE w.user_id = $1 AND w.workout_id = ANY($2::text[]) AND ${countedWorkoutSql("w")}
		ORDER BY w.device_end_date DESC`,
    [userId, workoutIds],
  );
  // Newest uploaded workout per holiday date (rows are newest-first).
  const byDate = new Map<string, { key: HolidayKey; workoutId: string }>();
  for (const r of rows) {
    const key = holidayKeyForLocalDate(r.local_date);
    if (key && !byDate.has(r.local_date)) {
      byDate.set(r.local_date, { key, workoutId: r.workout_id });
    }
  }
  if (byDate.size === 0) return [];

  const qualifying = await db.query<{ local_date: string }>(
    `SELECT to_char(w.local_date, 'YYYY-MM-DD') AS local_date
		FROM workouts w
		JOIN users u ON u.user_id = w.user_id
		WHERE w.user_id = $1 AND w.local_date = ANY($2::date[]) AND ${countedWorkoutSql("w")}
		GROUP BY w.local_date, u.goal_miles
		HAVING ${holidayDayQualifiesSql("u", "w")}`,
    [userId, [...byDate.keys()]],
  );
  const seen = new Set<HolidayKey>();
  const out: Array<{ key: HolidayKey; workoutId: string }> = [];
  for (const { local_date } of qualifying) {
    const hit = byDate.get(local_date);
    if (hit && !seen.has(hit.key)) {
      seen.add(hit.key);
      out.push(hit);
    }
  }
  return out;
}

/**
 * Every holiday the user's CURRENT counted history still has a goal day on.
 * Revocation only, and only for a user who holds a holiday medal.
 */
async function holidaysStillEarned(userId: string): Promise<Set<HolidayKey>> {
  const probe = holidayProbeDates();
  const rows = await db.query<{ local_date: string }>(
    `SELECT to_char(w.local_date, 'YYYY-MM-DD') AS local_date
		FROM workouts w
		JOIN users u ON u.user_id = w.user_id
		WHERE w.user_id = $1 AND w.local_date = ANY($2::date[]) AND ${countedWorkoutSql("w")}
		GROUP BY w.local_date, u.goal_miles
		HAVING ${holidayDayQualifiesSql("u", "w")}`,
    [userId, probe.map((p) => p.date)],
  );
  const out = new Set<HolidayKey>();
  for (const { local_date } of rows) {
    const key = holidayKeyForLocalDate(local_date);
    if (key) out.add(key);
  }
  return out;
}

/**
 * Every holiday the user's counted history has a goal day on, over ALL of it
 * — Recalibrate and the retro sweep (the sync path judges only the days an
 * upload touched). Same rule and same attribution as the one-time holiday
 * backfill: the EARLIEST qualifying day per holiday, its newest counted
 * workout as the trigger. A trigger that old sits outside the upload
 * controller's 24h push gate by construction.
 */
async function holidayHitsAllHistory(
  userId: string,
): Promise<Array<{ key: HolidayKey; workoutId: string }>> {
  const probe = holidayProbeDates();
  const rows = await db.query<{ local_date: string; workout_id: string }>(
    `SELECT to_char(w.local_date, 'YYYY-MM-DD') AS local_date,
		        (ARRAY_AGG(w.workout_id ORDER BY w.device_end_date DESC))[1] AS workout_id
		FROM workouts w
		JOIN users u ON u.user_id = w.user_id
		WHERE w.user_id = $1 AND w.local_date = ANY($2::date[]) AND ${countedWorkoutSql("w")}
		GROUP BY w.local_date, u.goal_miles
		HAVING ${holidayDayQualifiesSql("u", "w")}
		ORDER BY w.local_date ASC`,
    [userId, probe.map((p) => p.date)],
  );
  const out: Array<{ key: HolidayKey; workoutId: string }> = [];
  const seen = new Set<HolidayKey>();
  for (const r of rows) {
    const key = holidayKeyForLocalDate(r.local_date);
    if (key && !seen.has(key)) {
      seen.add(key);
      out.push({ key, workoutId: r.workout_id });
    }
  }
  return out;
}

// Returns { earned: bool, aggregateOnly: bool }.
// aggregateOnly = badge derives from aggregates and can't be pinned to a single workout.
function evaluatePredicate(
  badge: Badge,
  agg: UserAggregates,
): { earned: boolean; aggregateOnly: boolean } {
  const req = badge.requirement !== null ? Number(badge.requirement) : null;

  switch (badge.category) {
    case "streak":
      return {
        // LONGEST run ever, never just the current one — see
        // computeStreakAggregates.
        earned: req !== null && agg.longestStreak >= req,
        aggregateOnly: false,
      };
    case "miles":
      return {
        earned: req !== null && agg.totalMiles >= req,
        aggregateOnly: false,
      };
    case "pace":
      return {
        earned:
          req !== null &&
          agg.fastestSplitPaceMinMi > 0 &&
          agg.fastestSplitPaceMinMi <= req,
        aggregateOnly: false,
      };
    case "daily_distance":
      return {
        earned: req !== null && agg.mostMilesInOneDay >= req,
        aggregateOnly: false,
      };
    case "challenge":
      return {
        earned: req !== null && agg.challengeCompletionsCount >= req,
        aggregateOnly: false,
      };
    case "special":
      if (badge.badgeId === "special_first_mile") {
        return { earned: agg.totalMiles >= 1.0, aggregateOnly: false };
      }
      if (badge.badgeId === "special_first_week") {
        return {
          earned: agg.longestStreak >= 7 && agg.totalMiles >= 7.0,
          aggregateOnly: true,
        };
      }
      return { earned: false, aggregateOnly: true };
    case "story":
      return {
        earned: req !== null && agg.storyPostsCount >= req,
        aggregateOnly: true,
      };
    case "hype":
      return {
        earned: req !== null && agg.hypesGivenCount >= req,
        aggregateOnly: true,
      };
    case "nudge":
      return {
        earned: req !== null && agg.nudgesSentCount >= req,
        aggregateOnly: true,
      };
    case "competition": {
      // One category, three families distinguished by badgeId prefix.
      if (req === null) return { earned: false, aggregateOnly: true };
      if (badge.badgeId.startsWith("comp_started_")) {
        return { earned: agg.competitionsStarted >= req, aggregateOnly: true };
      }
      if (badge.badgeId.startsWith("comp_won_")) {
        return { earned: agg.competitionsWon >= req, aggregateOnly: true };
      }
      // default: entered/participated
      return { earned: agg.competitionsEntered >= req, aggregateOnly: true };
    }
    case "buddy": {
      // Same badgeId-prefix family shape as `competition` above.
      if (req === null) return { earned: false, aggregateOnly: true };
      if (badge.badgeId.startsWith("buddy_crew_")) {
        return {
          earned: agg.buddyDistinctPartners >= req,
          aggregateOnly: true,
        };
      }
      if (badge.badgeId.startsWith("buddy_won_")) {
        return { earned: agg.buddySessionsWon >= req, aggregateOnly: true };
      }
      // default: completed sessions
      return { earned: agg.buddySessionsCompleted >= req, aggregateOnly: true };
    }
    case "ghost": {
      // ghost_beat_* = races won, ghost_margin_* = biggest single margin in
      // seconds. Same badgeId-prefix family shape as `buddy` above.
      if (req === null) return { earned: false, aggregateOnly: true };
      if (badge.badgeId.startsWith("ghost_margin_")) {
        return { earned: agg.bestGhostMargin >= req, aggregateOnly: true };
      }
      return { earned: agg.ghostsBeaten >= req, aggregateOnly: true };
    }
    case "weekly_challenge": {
      // weekly_streak_* = consecutive weeks, everything else = total completed.
      // Same badgeId-prefix family shape as `ghost` and `buddy` above.
      if (req === null) return { earned: false, aggregateOnly: true };
      if (badge.badgeId.startsWith("weekly_streak_")) {
        return {
          earned: agg.bestWeeklyChallengeStreak >= req,
          aggregateOnly: true,
        };
      }
      return {
        earned: agg.weeklyChallengesCompleted >= req,
        aggregateOnly: true,
      };
    }
    case "holiday":
      // Judged per DAY by evaluateHolidayBadges, never from aggregates.
      return { earned: false, aggregateOnly: false };
    default:
      return { earned: false, aggregateOnly: true };
  }
}

// ─── Orchestrator called from workout upload ────────────────────────

export async function evaluateWorkoutRewards(
  userId: string,
  newWorkoutIds: string[],
): Promise<RewardEvaluationResult> {
  const newChallengeCompletions = await evaluateChallengesForBatch(
    userId,
    newWorkoutIds,
  );
  // Weekly metrics are cumulative, so this recomputes the whole week rather
  // than looking at what just arrived. Swallowed on failure: a weekly-challenge
  // problem must never fail a workout upload.
  const newWeeklyCompletion = await evaluateWeeklyChallengeForUser(
    userId,
  ).catch((error: any) => {
    console.error(
      "[WeeklyChallenges] Evaluation failed:",
      error?.message ?? error,
    );
    return null;
  });
  const { newlyEarnedBadges } = await evaluateForUser(userId, newWorkoutIds);
  return { newlyEarnedBadges, newChallengeCompletions, newWeeklyCompletion };
}

/**
 * Re-evaluate badges after a non-workout action (post, hype, competition).
 * Best-effort — callers fire-and-forget; never let a badge error break the
 * underlying action. Returns the newly-earned badges (empty on any failure).
 */
export async function evaluateSocialBadgesForUser(
  userId: string,
): Promise<UserBadge[]> {
  try {
    const { newlyEarnedBadges } = await evaluateForUser(userId, []);
    return newlyEarnedBadges;
  } catch (e: any) {
    console.error("[badges] social evaluation failed:", e?.message ?? e);
    return [];
  }
}

/**
 * Recalibrate Medals: judge EVERY category over the user's whole history and
 * award whatever they have earned but don't hold. The Recalibrate Streak
 * action runs it right after refreshCurrentStreak (a repaired history is
 * exactly when a missing medal turns up), and the retro sweep
 * (db/backfillRetroBadges.ts) runs it for everyone once.
 *
 * AWARD-ONLY, deliberately. It never revokes, even where the recount now
 * disagrees with a medal held: medals unlock Flamey cosmetics, a Recalibrate
 * is something a user taps to FIX their account, and a medal that silently
 * vanishes from under an outfit is a far worse outcome than one kept. The one
 * revocation path stays revokeUnearnedBadges, run only on a workout DELETION
 * or exclusion — i.e. when the user's history actually lost something.
 *
 * Returns the newly-awarded medals (empty when nothing was missing), which
 * makes it idempotent: a second run awards nothing.
 */
export async function recalibrateBadges(
  userId: string,
  source: "recalibrate" | "retro_sweep" = "recalibrate",
): Promise<UserBadge[]> {
  const { newlyEarnedBadges } = await evaluateForUser(userId, [], {
    allHolidays: true,
    source,
  });
  return newlyEarnedBadges;
}

// ─── Revocation (after a workout is deleted/excluded) ───────────────

/** Social/app-function badges are not workout-derived, so a workout deletion
 * never revokes them. */
function isWorkoutDerived(category: BadgeCategory): boolean {
  return !(
    (
      category === "story" ||
      category === "hype" ||
      category === "nudge" ||
      category === "competition" ||
      // Buddy medals derive from completed SESSIONS, not from workout history.
      // Deleting a workout must not strip the medal for a walk you genuinely
      // did with a friend — and the friend's copy of that session still exists.
      category === "buddy"
    )
    // Ghost medals are deliberately NOT listed here: the win lives on the
    // workout row itself, so deleting that workout should take the medal
    // with it, exactly like a pace badge.
  );
}

/**
 * Remove any earned badges the user no longer qualifies for after their active
 * workout history changed (a deletion or auto-exclusion). Workout-derived badges
 * are checked against recomputed aggregates, using the max-ever streak so a real
 * historical achievement is never stripped. Returns the revoked badge ids.
 */
export async function revokeUnearnedBadges(userId: string): Promise<string[]> {
  const [agg, catalog, earnedRows] = await Promise.all([
    computeAggregates(userId),
    getCatalog(),
    db.query<{ badge_id: string }>(
      `SELECT badge_id FROM user_badges WHERE user_id = $1`,
      [userId],
    ),
  ]);
  const byId = new Map(catalog.map((b) => [b.badgeId, b]));
  // "Ever earned" semantics: streak/special badges are judged on
  // agg.longestStreak — the best run the real history can still produce, the
  // SAME measure the award uses (deleting a bogus drive that bridged a run
  // drops the medal; a real past streak that simply isn't current keeps it).
  const aggForEarn: UserAggregates = agg;

  // Holiday medals: kept while ANY goal day on that holiday (any year)
  // survives in the counted history — deleting the only Halloween walk takes
  // the Spooky Mile with it, exactly like a pace badge; deleting one of two
  // Halloweens doesn't. Only queried when the user holds one.
  const holdsHoliday = earnedRows.some(
    (r) => holidayKeyFromBadgeId(r.badge_id) !== null,
  );
  const stillHoliday = holdsHoliday
    ? await holidaysStillEarned(userId)
    : new Set<HolidayKey>();

  const toRevoke: string[] = [];
  for (const { badge_id } of earnedRows) {
    const badge = byId.get(badge_id);
    if (!badge) continue; // unknown/legacy badge — leave it alone
    if (!isWorkoutDerived(badge.category)) continue;
    if (badge.category === "holiday") {
      const key = holidayKeyFromBadgeId(badge_id);
      if (key && !stillHoliday.has(key)) toRevoke.push(badge_id);
      continue;
    }
    if (!evaluatePredicate(badge, aggForEarn).earned) {
      toRevoke.push(badge_id);
    }
  }

  if (toRevoke.length > 0) {
    await db.query(
      `DELETE FROM user_badges WHERE user_id = $1 AND badge_id = ANY($2::text[])`,
      [userId, toRevoke],
    );
  }
  return toRevoke;
}

// ─── Catalog seed for the v2 social / app-function badges ───────────
// Idempotent: inserts the new badge rows if they're missing so dev + prod
// pick them up on deploy without a manual SQL step. Never updates existing rows.
const EXTRA_BADGES: Array<{
  badgeId: string;
  category: BadgeCategory;
  name: string;
  description: string;
  icon: string;
  rarity: "common" | "rare" | "legendary";
  requirement: number | null;
  sortOrder: number;
}> = [
  // Stories
  {
    badgeId: "story_1",
    category: "story",
    name: "First Story",
    description: "Shared your first story photo",
    icon: "camera.fill",
    rarity: "common",
    requirement: 1,
    sortOrder: 900,
  },
  {
    badgeId: "story_5",
    category: "story",
    name: "Storyteller",
    description: "Shared 5 story photos",
    icon: "photo.stack.fill",
    rarity: "common",
    requirement: 5,
    sortOrder: 901,
  },
  {
    badgeId: "story_25",
    category: "story",
    name: "Documentarian",
    description: "Shared 25 story photos",
    icon: "photo.on.rectangle.angled",
    rarity: "rare",
    requirement: 25,
    sortOrder: 902,
  },
  {
    badgeId: "story_100",
    category: "story",
    name: "Highlight Reel",
    description: "Shared 100 story photos",
    icon: "film.stack.fill",
    rarity: "legendary",
    requirement: 100,
    sortOrder: 903,
  },
  // Hype
  {
    badgeId: "hype_1",
    category: "hype",
    name: "First Hype",
    description: "Hyped a friend for the first time",
    icon: "hands.clap.fill",
    rarity: "common",
    requirement: 1,
    sortOrder: 910,
  },
  {
    badgeId: "hype_25",
    category: "hype",
    name: "Hype Man",
    description: "Sent 25 hypes",
    icon: "hands.clap.fill",
    rarity: "common",
    requirement: 25,
    sortOrder: 911,
  },
  {
    badgeId: "hype_100",
    category: "hype",
    name: "Cheerleader",
    description: "Sent 100 hypes",
    icon: "megaphone.fill",
    rarity: "rare",
    requirement: 100,
    sortOrder: 912,
  },
  {
    badgeId: "hype_500",
    category: "hype",
    name: "Hype Machine",
    description: "Sent 500 hypes",
    icon: "party.popper.fill",
    rarity: "legendary",
    requirement: 500,
    sortOrder: 913,
  },
  // Nudges (accountability — reminding friends to get their mile in)
  {
    badgeId: "nudge_1",
    category: "nudge",
    name: "First Nudge",
    description: "Nudged a friend to get their mile in",
    icon: "hand.wave.fill",
    rarity: "common",
    requirement: 1,
    sortOrder: 950,
  },
  {
    badgeId: "nudge_25",
    category: "nudge",
    name: "Motivator",
    description: "Sent 25 nudges",
    icon: "bell.badge.fill",
    rarity: "common",
    requirement: 25,
    sortOrder: 951,
  },
  {
    badgeId: "nudge_100",
    category: "nudge",
    name: "Accountability Partner",
    description: "Sent 100 nudges",
    icon: "bell.badge.fill",
    rarity: "rare",
    requirement: 100,
    sortOrder: 952,
  },
  {
    badgeId: "nudge_500",
    category: "nudge",
    name: "Hype Coach",
    description: "Sent 500 nudges",
    icon: "megaphone.fill",
    rarity: "legendary",
    requirement: 500,
    sortOrder: 953,
  },
  // Competitions started
  {
    badgeId: "comp_started_1",
    category: "competition",
    name: "Game On",
    description: "Started your first competition",
    icon: "flag.checkered",
    rarity: "common",
    requirement: 1,
    sortOrder: 920,
  },
  {
    badgeId: "comp_started_10",
    category: "competition",
    name: "Organizer",
    description: "Started 10 competitions",
    icon: "flag.checkered.2.crossed",
    rarity: "rare",
    requirement: 10,
    sortOrder: 921,
  },
  // Competitions entered
  {
    badgeId: "comp_entered_1",
    category: "competition",
    name: "Challenger",
    description: "Joined your first competition",
    icon: "figure.run",
    rarity: "common",
    requirement: 1,
    sortOrder: 930,
  },
  {
    badgeId: "comp_entered_10",
    category: "competition",
    name: "Competitor",
    description: "Competed in 10 competitions",
    icon: "trophy.fill",
    rarity: "rare",
    requirement: 10,
    sortOrder: 931,
  },
  {
    badgeId: "comp_entered_50",
    category: "competition",
    name: "Seasoned",
    description: "Competed in 50 competitions",
    icon: "trophy.fill",
    rarity: "legendary",
    requirement: 50,
    sortOrder: 932,
  },
  // Competitions won
  {
    badgeId: "comp_won_1",
    category: "competition",
    name: "Champion",
    description: "Won your first competition",
    icon: "crown.fill",
    rarity: "rare",
    requirement: 1,
    sortOrder: 940,
  },
  {
    badgeId: "comp_won_5",
    category: "competition",
    name: "Dominator",
    description: "Won 5 competitions",
    icon: "crown.fill",
    rarity: "legendary",
    requirement: 5,
    sortOrder: 941,
  },
  {
    badgeId: "comp_won_25",
    category: "competition",
    name: "Hall of Famer",
    description: "Won 25 competitions",
    icon: "crown.fill",
    rarity: "legendary",
    requirement: 25,
    sortOrder: 942,
  },
  // ── Buddy Walks ──
  // Three families by badgeId prefix (see evaluatePredicate's "buddy" case):
  // buddy_done_* = completed sessions, buddy_crew_* = distinct people walked
  // with, buddy_won_* = races won. Cooperative modes never declare a winner,
  // so the buddy_won_ family is reachable only through race modes.
  //
  // SF Symbols note: `figure.2` ships in SF Symbols 4 (iOS 16), so it renders
  // on the iOS 17 deployment target. Avoid anything newer here — a too-new
  // symbol renders as a BLANK box on iOS 17, not a fallback.
  {
    badgeId: "buddy_done_1",
    category: "buddy",
    name: "Better Together",
    description: "Finished your first buddy walk",
    icon: "figure.2",
    rarity: "common",
    requirement: 1,
    sortOrder: 950,
  },
  {
    badgeId: "buddy_done_10",
    category: "buddy",
    name: "Walking Partner",
    description: "Finished 10 buddy walks",
    icon: "figure.2",
    rarity: "rare",
    requirement: 10,
    sortOrder: 951,
  },
  {
    badgeId: "buddy_done_50",
    category: "buddy",
    name: "Inseparable",
    description: "Finished 50 buddy walks",
    icon: "figure.2",
    rarity: "legendary",
    requirement: 50,
    sortOrder: 952,
  },
  {
    badgeId: "buddy_crew_3",
    category: "buddy",
    name: "Small Crew",
    description: "Walked with 3 different friends",
    icon: "person.3.fill",
    rarity: "common",
    requirement: 3,
    sortOrder: 953,
  },
  {
    badgeId: "buddy_crew_10",
    category: "buddy",
    name: "Whole Crew",
    description: "Walked with 10 different friends",
    icon: "person.3.fill",
    rarity: "rare",
    requirement: 10,
    sortOrder: 954,
  },
  {
    badgeId: "buddy_won_1",
    category: "buddy",
    name: "Photo Finish",
    description: "Won your first buddy race",
    icon: "flag.checkered",
    rarity: "rare",
    requirement: 1,
    sortOrder: 955,
  },
  {
    badgeId: "buddy_won_10",
    category: "buddy",
    name: "Pace Setter",
    description: "Won 10 buddy races",
    icon: "flag.checkered",
    rarity: "legendary",
    requirement: 10,
    sortOrder: 956,
  },
  // ── Ghost Races ──
  // Two families by badgeId prefix (see evaluatePredicate's "ghost" case):
  // ghost_beat_* = races won, ghost_margin_* = biggest single winning margin
  // in seconds. A race is only counted when it was WON — the tracker stamps
  // `workouts.ghost_margin_seconds` on a win and nothing else.
  //
  // SF Symbols note: there is no ghost symbol on the iOS 17 deployment target
  // (a too-new symbol renders as a BLANK box, not a fallback), so these use
  // shipped symbols. The app draws its own ghost where the character matters.
  {
    badgeId: "ghost_beat_1",
    category: "ghost",
    name: "Ghost Hunter",
    description: "Beat a ghost over the mile for the first time",
    icon: "flag.checkered",
    rarity: "common",
    requirement: 1,
    sortOrder: 960,
  },
  {
    badgeId: "ghost_beat_10",
    category: "ghost",
    name: "Ghost Buster",
    description: "Beat your ghost 10 times",
    icon: "flag.checkered",
    rarity: "rare",
    requirement: 10,
    sortOrder: 961,
  },
  {
    badgeId: "ghost_beat_50",
    category: "ghost",
    name: "Unhaunted",
    description: "Beat your ghost 50 times",
    icon: "flag.checkered",
    rarity: "legendary",
    requirement: 50,
    sortOrder: 962,
  },
  {
    badgeId: "ghost_margin_15",
    category: "ghost",
    name: "Clear Daylight",
    description: "Beat a ghost by 15 seconds or more",
    icon: "bolt.fill",
    rarity: "rare",
    requirement: 15,
    sortOrder: 963,
  },
  {
    badgeId: "ghost_margin_45",
    category: "ghost",
    name: "Vanishing Act",
    description: "Beat a ghost by 45 seconds or more",
    icon: "bolt.fill",
    rarity: "legendary",
    requirement: 45,
    sortOrder: 964,
  },
  // Weekly challenges. `weekly_streak_*` reads the consecutive-weeks
  // aggregate; the rest read the total completed. Icons are SF Symbols 5 or
  // earlier — anything newer renders as a blank box on iOS 17.
  {
    badgeId: "weekly_1",
    category: "weekly_challenge",
    name: "Week One",
    description: "Completed your first weekly challenge",
    icon: "calendar.badge.checkmark",
    rarity: "common",
    requirement: 1,
    sortOrder: 970,
  },
  {
    badgeId: "weekly_5",
    category: "weekly_challenge",
    name: "Regular",
    description: "Completed 5 weekly challenges",
    icon: "calendar.badge.checkmark",
    rarity: "common",
    requirement: 5,
    sortOrder: 971,
  },
  {
    badgeId: "weekly_10",
    category: "weekly_challenge",
    name: "Every Week Counts",
    description: "Completed 10 weekly challenges",
    icon: "calendar.badge.checkmark",
    rarity: "rare",
    requirement: 10,
    sortOrder: 972,
  },
  {
    badgeId: "weekly_25",
    category: "weekly_challenge",
    name: "Season Veteran",
    description: "Completed 25 weekly challenges",
    icon: "calendar.badge.checkmark",
    rarity: "legendary",
    requirement: 25,
    sortOrder: 973,
  },
  {
    badgeId: "weekly_streak_4",
    category: "weekly_challenge",
    name: "Full Month",
    description: "Completed the weekly challenge 4 weeks in a row",
    icon: "flame.fill",
    rarity: "rare",
    requirement: 4,
    sortOrder: 974,
  },
  {
    badgeId: "weekly_streak_12",
    category: "weekly_challenge",
    name: "Unbroken",
    description: "Completed the weekly challenge 12 weeks in a row",
    icon: "flame.fill",
    rarity: "legendary",
    requirement: 12,
    sortOrder: 975,
  },
  // Holiday medals — one per HOLIDAYS entry, evergreen (earned once, ever).
  // No numeric requirement: the rule is "goal met on that local day".
  ...HOLIDAYS.map((h, i) => ({
    badgeId: holidayBadgeId(h.key),
    category: "holiday" as const,
    name: h.medalName,
    description: `Walked or ran your mile on ${h.holidayName}.`,
    icon: h.icon,
    rarity: "rare" as const,
    requirement: null,
    sortOrder: 990 + i,
  })),
];

export async function seedExtraBadges(): Promise<void> {
  try {
    const queries = EXTRA_BADGES.map((b) => ({
      query: `INSERT INTO badges (badge_id, category, name, description, icon, rarity, requirement, is_hidden, sort_order)
				VALUES ($1, $2, $3, $4, $5, $6, $7, false, $8)
				ON CONFLICT (badge_id) DO NOTHING`,
      params: [
        b.badgeId,
        b.category,
        b.name,
        b.description,
        b.icon,
        b.rarity,
        b.requirement,
        b.sortOrder,
      ],
    }));
    await db.transaction(queries);
    console.log(
      `[badges] Seeded ${EXTRA_BADGES.length} social/app-function badges (idempotent).`,
    );
  } catch (e: any) {
    console.error("[badges] seedExtraBadges failed:", e?.message ?? e);
  }
}

// ─── Row mappers ────────────────────────────────────────────────────

function rowToBadge(row: any): Badge {
  return {
    badgeId: row.badge_id,
    category: row.category,
    name: row.name,
    description: row.description,
    icon: row.icon,
    rarity: row.rarity,
    requirement: row.requirement !== null ? Number(row.requirement) : null,
    isHidden: row.is_hidden,
    sortOrder: row.sort_order,
  };
}

function rowToUserBadge(row: any): UserBadge {
  return {
    badgeId: row.badge_id,
    category: row.category,
    name: row.name,
    description: row.description,
    icon: row.icon,
    rarity: row.rarity,
    requirement: row.requirement !== null ? Number(row.requirement) : null,
    isHidden: row.is_hidden,
    earnedAt:
      row.earned_at instanceof Date
        ? row.earned_at.toISOString()
        : String(row.earned_at),
    isNew: row.is_new,
    pinSlot: row.pin_slot ?? null,
    triggeringWorkoutId: row.triggering_workout_id,
    progressSnapshot: row.progress_snapshot,
  };
}

function roundTo(n: number, places: number): number {
  const m = Math.pow(10, places);
  return Math.round(n * m) / m;
}
