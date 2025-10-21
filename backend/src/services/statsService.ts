import { PostgresService } from './DbService.js';
import { UserStats, Badge, UpdateStatsRequest } from '../types/stats.js';

const db = PostgresService.getInstance();

/**
 * Get user stats and badges
 */
export async function getUserStats(userId: string): Promise<{ stats: UserStats; badges: Badge[] }> {
	// Get user stats from users table
	const statsResults = await db.query<UserStats>(
		`SELECT
			user_id,
			streak,
			total_miles,
			fastest_mile_pace,
			most_miles_in_one_day,
			last_completion_date,
			goal_miles
		FROM users
		WHERE user_id = $1`,
		[userId]
	);

	if (statsResults.length === 0) {
		throw new Error('User not found');
	}

	const stats = statsResults[0];

	// Get user badges
	const badgesResults = await db.query<Badge>(
		`SELECT
			badge_id,
			user_id,
			badge_key,
			name,
			description,
			date_awarded,
			is_new
		FROM badges
		WHERE user_id = $1
		ORDER BY date_awarded DESC`,
		[userId]
	);

	return {
		stats,
		badges: badgesResults
	};
}

/**
 * Update user stats
 */
export async function updateUserStats(userId: string, updates: UpdateStatsRequest): Promise<void> {
	const { streak, total_miles, fastest_mile_pace, most_miles_in_one_day, last_completion_date, goal_miles } = updates;

	await db.query(
		`UPDATE users
		SET
			streak = $1,
			total_miles = $2,
			fastest_mile_pace = $3,
			most_miles_in_one_day = $4,
			last_completion_date = $5,
			goal_miles = COALESCE($6, goal_miles)
		WHERE user_id = $7`,
		[
			streak,
			total_miles,
			fastest_mile_pace,
			most_miles_in_one_day,
			last_completion_date || null,
			goal_miles || null,
			userId
		]
	);
}

/**
 * Add a badge to user
 */
export async function addBadge(badge: Omit<Badge, 'badge_id'>): Promise<void> {
	await db.query(
		`INSERT INTO badges (user_id, badge_key, name, description, date_awarded, is_new)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (user_id, badge_key) DO NOTHING`,
		[badge.user_id, badge.badge_key, badge.name, badge.description, badge.date_awarded, badge.is_new]
	);
}

/**
 * Add multiple badges to user
 */
export async function addBadges(userId: string, badges: Omit<Badge, 'badge_id' | 'user_id'>[]): Promise<void> {
	if (badges.length === 0) return;

	const queries = badges.map((badge) => ({
		query: `INSERT INTO badges (user_id, badge_key, name, description, date_awarded, is_new)
				VALUES ($1, $2, $3, $4, $5, $6)
				ON CONFLICT (user_id, badge_key) DO NOTHING`,
		params: [userId, badge.badge_key, badge.name, badge.description, badge.date_awarded, badge.is_new]
	}));

	await db.transaction(queries);
}

/**
 * Mark all badges as viewed for a user
 */
export async function markBadgesAsViewed(userId: string): Promise<void> {
	await db.query(`UPDATE badges SET is_new = FALSE WHERE user_id = $1`, [userId]);
}

/**
 * Delete a badge from user
 */
export async function deleteBadge(userId: string, badgeKey: string): Promise<void> {
	await db.query(`DELETE FROM badges WHERE user_id = $1 AND badge_key = $2`, [userId, badgeKey]);
}
