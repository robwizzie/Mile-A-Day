import { PostgresService } from "./DbService.js";
import type {
  Badge,
  UserBadge,
  UserAggregates,
  RewardEvaluationResult,
  BadgeCategory,
} from "../types/badge.js";
import { evaluateChallengesForBatch } from "./dailyChallengeService.js";

const db = PostgresService.getInstance();

const STREAK_QUALIFYING_DISTANCE = 0.95;

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

export async function computeAggregates(
  userId: string,
): Promise<UserAggregates> {
  const [streakRow, totalsRow, paceRow, bestDayRow, ccRow] = await Promise.all([
    computeCurrentStreak(userId),
    db.query<{ total_miles: string | null }>(
      `SELECT COALESCE(SUM(distance),0)::text AS total_miles FROM workouts WHERE user_id = $1`,
      [userId],
    ),
    db.query<{ min_pace: string | null }>(
      `SELECT MIN(s.split_pace)::text AS min_pace
			FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
			WHERE w.user_id = $1 AND s.split_pace > 0 AND s.split_distance >= 0.95`,
      [userId],
    ),
    db.query<{ best_day: string | null }>(
      `SELECT COALESCE(MAX(day_total),0)::text AS best_day FROM (
				SELECT SUM(distance) AS day_total FROM workouts WHERE user_id = $1 GROUP BY local_date
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
    currentStreak: streakRow,
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
  competitionsStarted: number;
  competitionsEntered: number;
  competitionsWon: number;
}> {
  const zero = {
    storyPostsCount: 0,
    hypesGivenCount: 0,
    competitionsStarted: 0,
    competitionsEntered: 0,
    competitionsWon: 0,
  };
  try {
    const [stories, hypes, started, entered, won] = await Promise.all([
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
          `SELECT COUNT(*)::text AS count FROM hype_log WHERE sender_id = $1`,
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
    ]);
    return {
      storyPostsCount: parseInt(stories[0]?.count ?? "0", 10) || 0,
      hypesGivenCount: parseInt(hypes[0]?.count ?? "0", 10) || 0,
      competitionsStarted: parseInt(started[0]?.count ?? "0", 10) || 0,
      competitionsEntered: parseInt(entered[0]?.count ?? "0", 10) || 0,
      competitionsWon: parseInt(won[0]?.count ?? "0", 10) || 0,
    };
  } catch {
    return zero;
  }
}

// Longest trailing run of consecutive local_dates where SUM(distance) >= 0.95.
// "Current streak" = ending at the most recent qualifying day (not necessarily today).
async function computeCurrentStreak(userId: string): Promise<number> {
  const rows = await db.query<{ local_date: string; total: string }>(
    `SELECT local_date::text AS local_date, SUM(distance)::text AS total
		FROM workouts
		WHERE user_id = $1
		GROUP BY local_date
		ORDER BY local_date DESC`,
    [userId],
  );
  if (rows.length === 0) return 0;

  // Skip leading days until we find a qualifying one — that's the streak endpoint.
  let i = 0;
  while (
    i < rows.length &&
    parseFloat(rows[i].total) < STREAK_QUALIFYING_DISTANCE
  )
    i++;
  if (i >= rows.length) return 0;

  let streak = 1;
  let prevDate = rows[i].local_date;
  for (let j = i + 1; j < rows.length; j++) {
    const currDate = rows[j].local_date;
    if (!isPreviousDay(currDate, prevDate)) break;
    if (parseFloat(rows[j].total) < STREAK_QUALIFYING_DISTANCE) break;
    streak++;
    prevDate = currDate;
  }
  return streak;
}

function isPreviousDay(earlierYmd: string, laterYmd: string): boolean {
  const [y1, m1, d1] = earlierYmd.split("-").map((n) => parseInt(n, 10));
  const [y2, m2, d2] = laterYmd.split("-").map((n) => parseInt(n, 10));
  const earlier = Date.UTC(y1, m1 - 1, d1);
  const later = Date.UTC(y2, m2 - 1, d2);
  return later - earlier === 86400000;
}

// ─── Evaluator ──────────────────────────────────────────────────────

export async function evaluateForUser(
  userId: string,
  newWorkoutIds: string[],
): Promise<{ newlyEarnedBadges: UserBadge[] }> {
  const [aggregates, catalog, earned] = await Promise.all([
    computeAggregates(userId),
    getCatalog(),
    getEarnedBadgeIds(userId),
  ]);

  const triggeringWorkoutId = newWorkoutIds[newWorkoutIds.length - 1] ?? null;
  const snapshot = {
    streak: aggregates.currentStreak,
    totalMiles: roundTo(aggregates.totalMiles, 2),
    fastestMilePace: roundTo(aggregates.fastestSplitPaceMinMi, 3),
    mostMilesInOneDay: roundTo(aggregates.mostMilesInOneDay, 2),
    challengeCompletions: aggregates.challengeCompletionsCount,
  };

  const toInsert: { badgeId: string; aggregateOnly: boolean }[] = [];

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

  if (toInsert.length === 0) {
    return { newlyEarnedBadges: [] };
  }

  const queries = toInsert.map(({ badgeId, aggregateOnly }) => ({
    query: `INSERT INTO user_badges (user_id, badge_id, triggering_workout_id, progress_snapshot)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (user_id, badge_id) DO NOTHING`,
    params: [
      userId,
      badgeId,
      aggregateOnly ? null : triggeringWorkoutId,
      JSON.stringify(snapshot),
    ],
  }));
  await db.transaction(queries);

  const insertedIds = toInsert.map((t) => t.badgeId);
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
        earned: req !== null && agg.currentStreak >= req,
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
          earned: agg.currentStreak >= 7 && agg.totalMiles >= 7.0,
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
  const { newlyEarnedBadges } = await evaluateForUser(userId, newWorkoutIds);
  return { newlyEarnedBadges, newChallengeCompletions };
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
  requirement: number;
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
