import { PostgresService } from './DbService.js';
import type {
	Badge,
	UserBadge,
	UserAggregates,
	RewardEvaluationResult
} from '../types/badge.js';
import { evaluateChallengesForBatch } from './dailyChallengeService.js';

const db = PostgresService.getInstance();

const STREAK_QUALIFYING_DISTANCE = 0.95;

// ─── Catalog reads ──────────────────────────────────────────────────

export async function getCatalog(includeHidden: boolean): Promise<Badge[]> {
	const rows = await db.query<any>(
		`SELECT badge_id, category, name, description, icon, rarity, requirement, is_hidden, sort_order
		FROM badges
		${includeHidden ? '' : 'WHERE is_hidden = FALSE'}
		ORDER BY sort_order ASC`
	);
	return rows.map(rowToBadge);
}

export async function getUserBadges(userId: string): Promise<UserBadge[]> {
	const rows = await db.query<any>(
		`SELECT
			ub.badge_id, ub.earned_at, ub.is_new, ub.triggering_workout_id, ub.progress_snapshot,
			b.category, b.name, b.description, b.icon, b.rarity, b.requirement, b.is_hidden
		FROM user_badges ub
		JOIN badges b ON b.badge_id = ub.badge_id
		WHERE ub.user_id = $1
		ORDER BY ub.earned_at DESC`,
		[userId]
	);
	return rows.map(rowToUserBadge);
}

export async function markBadgesViewed(userId: string): Promise<number> {
	const rows = await db.query<{ id: number }>(
		`UPDATE user_badges SET is_new = FALSE WHERE user_id = $1 AND is_new = TRUE RETURNING id`,
		[userId]
	);
	return rows.length;
}

// ─── Aggregate computation ──────────────────────────────────────────

export async function computeAggregates(userId: string): Promise<UserAggregates> {
	const [streakRow, totalsRow, paceRow, bestDayRow, ccRow] = await Promise.all([
		computeCurrentStreak(userId),
		db.query<{ total_miles: string | null }>(
			`SELECT COALESCE(SUM(distance),0)::text AS total_miles FROM workouts WHERE user_id = $1`,
			[userId]
		),
		db.query<{ min_pace: string | null }>(
			`SELECT MIN(s.split_pace)::text AS min_pace
			FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
			WHERE w.user_id = $1 AND s.split_pace > 0 AND s.split_distance >= 0.95`,
			[userId]
		),
		db.query<{ best_day: string | null }>(
			`SELECT COALESCE(MAX(day_total),0)::text AS best_day FROM (
				SELECT SUM(distance) AS day_total FROM workouts WHERE user_id = $1 GROUP BY local_date
			) t`,
			[userId]
		),
		db.query<{ count: string }>(
			`SELECT COUNT(*)::text AS count FROM user_challenge_completions WHERE user_id = $1`,
			[userId]
		)
	]);

	const minPaceSeconds = paceRow[0]?.min_pace ? parseFloat(paceRow[0].min_pace) : 0;
	return {
		currentStreak: streakRow,
		totalMiles: parseFloat(totalsRow[0]?.total_miles ?? '0') || 0,
		fastestSplitPaceMinMi: minPaceSeconds > 0 ? minPaceSeconds / 60.0 : 0,
		mostMilesInOneDay: parseFloat(bestDayRow[0]?.best_day ?? '0') || 0,
		challengeCompletionsCount: parseInt(ccRow[0]?.count ?? '0', 10) || 0
	};
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
		[userId]
	);
	if (rows.length === 0) return 0;

	// Skip leading days until we find a qualifying one — that's the streak endpoint.
	let i = 0;
	while (i < rows.length && parseFloat(rows[i].total) < STREAK_QUALIFYING_DISTANCE) i++;
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
	const [y1, m1, d1] = earlierYmd.split('-').map(n => parseInt(n, 10));
	const [y2, m2, d2] = laterYmd.split('-').map(n => parseInt(n, 10));
	const earlier = Date.UTC(y1, m1 - 1, d1);
	const later = Date.UTC(y2, m2 - 1, d2);
	return later - earlier === 86400000;
}

// ─── Evaluator ──────────────────────────────────────────────────────

export async function evaluateForUser(
	userId: string,
	newWorkoutIds: string[]
): Promise<{ newlyEarnedBadges: UserBadge[] }> {
	const [aggregates, catalog, earned] = await Promise.all([
		computeAggregates(userId),
		getCatalog(true),
		getEarnedBadgeIds(userId)
	]);

	const triggeringWorkoutId = newWorkoutIds[newWorkoutIds.length - 1] ?? null;
	const snapshot = {
		streak: aggregates.currentStreak,
		totalMiles: roundTo(aggregates.totalMiles, 2),
		fastestMilePace: roundTo(aggregates.fastestSplitPaceMinMi, 3),
		mostMilesInOneDay: roundTo(aggregates.mostMilesInOneDay, 2),
		challengeCompletions: aggregates.challengeCompletionsCount
	};

	const toInsert: { badgeId: string; aggregateOnly: boolean }[] = [];

	for (const badge of catalog) {
		if (earned.has(badge.badgeId)) continue;
		const result = evaluatePredicate(badge, aggregates);
		if (result.earned) {
			toInsert.push({ badgeId: badge.badgeId, aggregateOnly: result.aggregateOnly });
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
			JSON.stringify(snapshot)
		]
	}));
	await db.transaction(queries);

	const insertedIds = toInsert.map(t => t.badgeId);
	const newlyEarnedBadges = await db.query<any>(
		`SELECT
			ub.badge_id, ub.earned_at, ub.is_new, ub.triggering_workout_id, ub.progress_snapshot,
			b.category, b.name, b.description, b.icon, b.rarity, b.requirement, b.is_hidden
		FROM user_badges ub
		JOIN badges b ON b.badge_id = ub.badge_id
		WHERE ub.user_id = $1 AND ub.badge_id = ANY($2::text[])
		ORDER BY ub.earned_at DESC`,
		[userId, insertedIds]
	);

	return { newlyEarnedBadges: newlyEarnedBadges.map(rowToUserBadge) };
}

async function getEarnedBadgeIds(userId: string): Promise<Set<string>> {
	const rows = await db.query<{ badge_id: string }>(
		`SELECT badge_id FROM user_badges WHERE user_id = $1`,
		[userId]
	);
	return new Set(rows.map(r => r.badge_id));
}

// Returns { earned: bool, aggregateOnly: bool }.
// aggregateOnly = badge derives from aggregates and can't be pinned to a single workout.
function evaluatePredicate(badge: Badge, agg: UserAggregates): { earned: boolean; aggregateOnly: boolean } {
	const req = badge.requirement !== null ? Number(badge.requirement) : null;

	switch (badge.category) {
		case 'streak':
			return { earned: req !== null && agg.currentStreak >= req, aggregateOnly: false };
		case 'miles':
			return { earned: req !== null && agg.totalMiles >= req, aggregateOnly: false };
		case 'pace':
			return {
				earned: req !== null && agg.fastestSplitPaceMinMi > 0 && agg.fastestSplitPaceMinMi <= req,
				aggregateOnly: false
			};
		case 'daily_distance':
			return { earned: req !== null && agg.mostMilesInOneDay >= req, aggregateOnly: false };
		case 'challenge':
			return { earned: req !== null && agg.challengeCompletionsCount >= req, aggregateOnly: false };
		case 'special':
			if (badge.badgeId === 'special_first_mile') {
				return { earned: agg.totalMiles >= 1.0, aggregateOnly: false };
			}
			if (badge.badgeId === 'special_first_week') {
				return { earned: agg.currentStreak >= 7 && agg.totalMiles >= 7.0, aggregateOnly: true };
			}
			return { earned: false, aggregateOnly: true };
		case 'hidden':
			return { earned: evaluateHidden(badge.badgeId, agg), aggregateOnly: true };
		default:
			return { earned: false, aggregateOnly: true };
	}
}

function evaluateHidden(badgeId: string, agg: UserAggregates): boolean {
	const pace = agg.fastestSplitPaceMinMi;
	switch (badgeId) {
		case 'hidden_perfect_10':
			return agg.mostMilesInOneDay >= 10.0 && agg.mostMilesInOneDay < 10.1;
		case 'hidden_lucky_7':
			return agg.currentStreak === 7 && agg.mostMilesInOneDay >= 7.0;
		case 'hidden_double_trouble':
			return agg.totalMiles >= 22.0 && agg.totalMiles < 23.0;
		case 'hidden_century_double':
			return agg.currentStreak >= 100 && agg.totalMiles >= 100;
		case 'hidden_speed_endurance':
			return pace > 0 && pace <= 8.0 && agg.mostMilesInOneDay >= 5.0;
		case 'hidden_marathon_pace':
			return pace > 0 && pace <= 10.0 && agg.mostMilesInOneDay >= 26.2;
		case 'hidden_triple_threat':
			return agg.currentStreak >= 30 && agg.totalMiles >= 30 && agg.mostMilesInOneDay >= 3.0;
		case 'hidden_50_50':
			return agg.currentStreak >= 50 && agg.totalMiles >= 50;
		case 'hidden_year_miles':
			return agg.totalMiles >= 365;
		case 'hidden_thousand_club':
			return agg.currentStreak >= 1000 || agg.totalMiles >= 1000;
		case 'hidden_pace_perfect':
			return pace > 0 && pace <= 7.0 && agg.mostMilesInOneDay >= 10.0;
		default:
			return false;
	}
}

// ─── Orchestrator called from workout upload ────────────────────────

export async function evaluateWorkoutRewards(
	userId: string,
	newWorkoutIds: string[]
): Promise<RewardEvaluationResult> {
	const newChallengeCompletions = await evaluateChallengesForBatch(userId, newWorkoutIds);
	const { newlyEarnedBadges } = await evaluateForUser(userId, newWorkoutIds);
	return { newlyEarnedBadges, newChallengeCompletions };
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
		sortOrder: row.sort_order
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
		earnedAt: row.earned_at instanceof Date ? row.earned_at.toISOString() : String(row.earned_at),
		isNew: row.is_new,
		triggeringWorkoutId: row.triggering_workout_id,
		progressSnapshot: row.progress_snapshot
	};
}

function roundTo(n: number, places: number): number {
	const m = Math.pow(10, places);
	return Math.round(n * m) / m;
}
