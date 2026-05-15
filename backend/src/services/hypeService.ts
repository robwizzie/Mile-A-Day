import { PostgresService } from './DbService.js';
import { hasUnlimitedActions } from './privilegedUsers.js';
import { START_OF_TODAY_ET_SQL, START_OF_TOMORROW_ET_SQL } from './dailyResetTime.js';

const db = PostgresService.getInstance();

export const HYPE_DAILY_LIMIT = 3;

/**
 * Count of hypes the sender has sent since midnight ET today.
 * The window resets at midnight America/New_York, not rolling 24h.
 */
export async function getDailyHypeCount(senderId: string): Promise<number> {
	const rows = await db.query<{ count: string }>(
		`SELECT COUNT(*)::text AS count FROM hype_log
		WHERE sender_id = $1
			AND created_at >= ${START_OF_TODAY_ET_SQL}`,
		[senderId]
	);
	return parseInt(rows[0]?.count ?? '0', 10);
}

/**
 * True if the sender has fewer than HYPE_DAILY_LIMIT hypes in the last 24h.
 * Privileged users bypass the cap.
 */
export async function canHype(senderId: string): Promise<boolean> {
	if (hasUnlimitedActions(senderId)) return true;
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
	const unlimited = hasUnlimitedActions(senderId);

	if (context) {
		const sql = unlimited
			? `INSERT INTO hype_log (sender_id, target_id, context_type, context_id, context_label)
				VALUES ($1, $2, $3, $4, $5)
				RETURNING id`
			: `INSERT INTO hype_log (sender_id, target_id, context_type, context_id, context_label)
				SELECT $1, $2, $3, $4, $5
				WHERE (
					SELECT COUNT(*) FROM hype_log
					WHERE sender_id = $1 AND created_at >= ${START_OF_TODAY_ET_SQL}
				) < ${HYPE_DAILY_LIMIT}
				RETURNING id`;
		const rows = await db.query<{ id: string }>(sql, [
			senderId,
			targetId,
			context.contextType,
			context.contextId,
			context.contextLabel
		]);
		return rows[0] ?? null;
	}

	const sql = unlimited
		? `INSERT INTO hype_log (sender_id, target_id) VALUES ($1, $2) RETURNING id`
		: `INSERT INTO hype_log (sender_id, target_id)
			SELECT $1, $2
			WHERE (
				SELECT COUNT(*) FROM hype_log
				WHERE sender_id = $1 AND created_at >= ${START_OF_TODAY_ET_SQL}
			) < ${HYPE_DAILY_LIMIT}
			RETURNING id`;
	const rows = await db.query<{ id: string }>(sql, [senderId, targetId]);
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
 * ISO timestamp when the sender's daily cap resets — midnight ET tomorrow.
 * Returns null if they have spare capacity right now.
 */
export async function getHypeResetsAt(senderId: string): Promise<string | null> {
	if (hasUnlimitedActions(senderId)) return null;
	const count = await getDailyHypeCount(senderId);
	if (count < HYPE_DAILY_LIMIT) return null;

	const rows = await db.query<{ resets_at: string }>(`SELECT ${START_OF_TOMORROW_ET_SQL}::text AS resets_at`);
	return rows[0]?.resets_at ?? null;
}
