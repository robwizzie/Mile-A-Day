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

export interface HypeContext {
	contextType: 'mile' | 'badge' | 'pr';
	contextId: string;
	contextLabel: string;
}

/**
 * Atomically insert a hype_log row only if the sender is still under the
 * daily limit. Optional context describes what was hyped (mile/badge/pr) and
 * enables dedupe via the partial unique index on (sender, target, ctx_type, ctx_id).
 * Returns the new row's id, or null if the limit was reached.
 *
 * Caller is responsible for the dedupe pre-check via `hasHypedContext`; this
 * function will surface a PG unique violation otherwise.
 */
export async function logHypeIfUnderLimit(
	senderId: string,
	targetId: string,
	context?: HypeContext
): Promise<{ id: string } | null> {
	if (context) {
		const rows = await db.query<{ id: string }>(
			`INSERT INTO hype_log (sender_id, target_id, context_type, context_id, context_label)
			SELECT $1, $2, $3, $4, $5
			WHERE (
				SELECT COUNT(*) FROM hype_log
				WHERE sender_id = $1 AND created_at > NOW() - INTERVAL '24 hours'
			) < ${HYPE_DAILY_LIMIT}
			RETURNING id`,
			[senderId, targetId, context.contextType, context.contextId, context.contextLabel]
		);
		return rows[0] ?? null;
	}
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
 * Returns true if the sender has already hyped this exact context.
 * Only meaningful when context is provided; legacy NULL-context hypes are not deduped.
 */
export async function hasHypedContext(
	senderId: string,
	targetId: string,
	contextType: string,
	contextId: string
): Promise<boolean> {
	const rows = await db.query<{ exists: boolean }>(
		`SELECT EXISTS (
			SELECT 1 FROM hype_log
			WHERE sender_id = $1 AND target_id = $2
				AND context_type = $3 AND context_id = $4
		) AS exists`,
		[senderId, targetId, contextType, contextId]
	);
	return rows[0]?.exists === true;
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
