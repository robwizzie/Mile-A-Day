import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

export interface UpsertDailyStepsResult {
	steps: number;
	updatedAt: string;
}

/**
 * Insert or update a user's step total for a given local date.
 * Uses GREATEST so out-of-order or stale POSTs cannot decrease the stored value
 * — HealthKit can deliver late samples.
 */
export async function upsertDailySteps(
	userId: string,
	localDate: string,
	steps: number,
	timezoneOffset: number
): Promise<UpsertDailyStepsResult> {
	const rows = await db.query<{ steps: number; updated_at: string }>(
		`INSERT INTO daily_steps (user_id, local_date, steps, timezone_offset)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (user_id, local_date)
		 DO UPDATE SET
		     steps = GREATEST(daily_steps.steps, EXCLUDED.steps),
		     timezone_offset = EXCLUDED.timezone_offset,
		     updated_at = NOW()
		 RETURNING steps, updated_at::text AS updated_at`,
		[userId, localDate, steps, timezoneOffset]
	);

	const row = rows[0];
	return {
		steps: row.steps,
		updatedAt: row.updated_at,
	};
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
	endDate?: string
): Promise<{ user_id: string; local_date: string; total_distance: number }[]> {
	if (userIds.length === 0) return [];

	const todaysDate = new Date().toISOString().split('T')[0];
	const start = new Date(startDate).toISOString().split('T')[0];
	const end = endDate ? new Date(endDate).toISOString().split('T')[0] : todaysDate;

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
