import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

export const HYPE_DAILY_LIMIT = 3;

/**
 * Count of hypes the sender has sent in the last 24 hours (rolling window).
 */
export async function getDailyHypeCount(senderId: string): Promise<number> {
	const rows = await db.query<{ count: string }>(
		`SELECT COUNT(*)::text AS count FROM hype_log
		WHERE sender_id = $1
			AND created_at > NOW() - INTERVAL '24 hours'`,
		[senderId]
	);
	return parseInt(rows[0]?.count ?? '0', 10);
}

/**
 * True if the sender has fewer than HYPE_DAILY_LIMIT hypes in the last 24h.
 */
export async function canHype(senderId: string): Promise<boolean> {
	const count = await getDailyHypeCount(senderId);
	return count < HYPE_DAILY_LIMIT;
}

/**
 * Atomically insert a hype_log row only if the sender is still under the
 * daily limit. Returns the new row's id, or null if the limit was reached.
 * The single statement closes the race between concurrent senders that a
 * pre-check + insert would leave open.
 */
export async function logHypeIfUnderLimit(senderId: string, targetId: string): Promise<{ id: string } | null> {
	const rows = await db.query<{ id: string }>(
		`INSERT INTO hype_log (sender_id, target_id)
		SELECT $1, $2
		WHERE (
			SELECT COUNT(*) FROM hype_log
			WHERE sender_id = $1 AND created_at > NOW() - INTERVAL '24 hours'
		) < ${HYPE_DAILY_LIMIT}
		RETURNING id`,
		[senderId, targetId]
	);
	return rows[0] ?? null;
}

/**
 * ISO timestamp when the sender's oldest in-window hype rolls off,
 * unlocking their next slot. Returns null if they have spare capacity.
 */
export async function getHypeResetsAt(senderId: string): Promise<string | null> {
	const count = await getDailyHypeCount(senderId);
	if (count < HYPE_DAILY_LIMIT) return null;

	const rows = await db.query<{ rolls_off: string }>(
		`SELECT (created_at + INTERVAL '24 hours')::text AS rolls_off
		FROM hype_log
		WHERE sender_id = $1
			AND created_at > NOW() - INTERVAL '24 hours'
		ORDER BY created_at ASC
		LIMIT 1`,
		[senderId]
	);
	return rows[0]?.rolls_off ?? null;
}
