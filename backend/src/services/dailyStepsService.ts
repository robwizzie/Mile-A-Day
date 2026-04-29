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
