import { PostgresService } from "./DbService.js";
import { hasUnlimitedHypes } from "./privilegedUsers.js";
import {
  START_OF_TODAY_ET_SQL,
  START_OF_TOMORROW_ET_SQL,
} from "./dailyResetTime.js";

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
    [senderId],
  );
  return parseInt(rows[0]?.count ?? "0", 10);
}

/**
 * True if the sender has fewer than HYPE_DAILY_LIMIT hypes in the last 24h.
 * Privileged users bypass the cap.
 */
export async function canHype(senderId: string): Promise<boolean> {
  if (await hasUnlimitedHypes(senderId)) return true;
  const count = await getDailyHypeCount(senderId);
  return count < HYPE_DAILY_LIMIT;
}

export interface HypeContext {
  contextType: "mile" | "badge" | "pr" | "challenge" | "post";
  contextId: string;
  contextLabel: string;
}

export interface ReceivedHype {
  sender_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  context_type: string | null;
  context_label: string | null;
  created_at: string;
}

/**
 * Recent hypes the user has RECEIVED, newest first, with sender info — powers
 * the "you got hyped" surface on the profile so it isn't push-only.
 */
export async function getReceivedHypes(
  userId: string,
  limit: number = 30,
): Promise<ReceivedHype[]> {
  const rows = await db.query<ReceivedHype>(
    `SELECT h.sender_id, u.username, u.first_name, u.last_name, u.profile_image_url,
			h.context_type, h.context_label, h.created_at
		FROM hype_log h
		JOIN users u ON u.user_id = h.sender_id
		WHERE h.target_id = $1
		ORDER BY h.created_at DESC
		LIMIT $2`,
    [userId, limit],
  );
  return rows;
}

export interface ContextHyper {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  created_at: string;
}

/**
 * Everyone who hyped one specific context (a post, or a user's daily mile),
 * newest first — powers the Instagram-style "who liked this" list behind the
 * hype tally. DISTINCT ON sender so pre-migration dual-keyed mile rows from
 * one person appear once, matching the feed's COUNT(DISTINCT sender_id).
 */
export async function getContextHypers(
  targetId: string,
  contextType: string,
  contextId: string,
  limit: number = 100,
): Promise<ContextHyper[]> {
  const rows = await db.query<ContextHyper>(
    `SELECT h.sender_id AS user_id, u.username, u.first_name, u.last_name,
			u.profile_image_url, h.created_at
		FROM (
			SELECT DISTINCT ON (sender_id) sender_id, created_at
			FROM hype_log
			WHERE target_id = $1 AND context_type = $2 AND context_id = $3
			ORDER BY sender_id, created_at DESC
		) h
		JOIN users u ON u.user_id = h.sender_id
		ORDER BY h.created_at DESC
		LIMIT $4`,
    [targetId, contextType, contextId, limit],
  );
  return rows;
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
  context?: HypeContext,
): Promise<{ id: string } | null> {
  const unlimited = await hasUnlimitedHypes(senderId);

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
      context.contextLabel,
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

// A 'mile' hype's canonical context id: `<userId>:<YYYY-MM-DD>` — one hype per
// friend's daily mile, regardless of which surface it was sent from.
const MILE_COMPOSITE_RE = /:(\d{4}-\d{2}-\d{2})$/;

/**
 * SQL fragment matching a mile hype row against a workout row by the canonical
 * user:local_date composite key. Legacy workout_id-keyed rows were collapsed
 * onto composites by migration 0012, so this is a plain equality now. Owns the
 * composite encoding so read sites can't drift from the write side.
 */
export function mileHypeKeyMatchSql(
  hypeAlias: string,
  workoutAlias: string,
): string {
  return `${hypeAlias}.context_id = (${workoutAlias}.user_id || ':' || ${workoutAlias}.local_date::text)`;
}

/**
 * Canonicalize a 'mile' hype context. The feed historically keys mile hypes by
 * workout_id while the notifications inbox keys them by `<userId>:<localDate>`;
 * we resolve a workout_id to the composite form so both surfaces write (and
 * dedupe on) the same key. A composite id is re-prefixed with the target so a
 * client can't write a key that pollutes another user's counts. Unresolvable
 * ids pass through unchanged.
 */
/** True when the string is a real calendar date, not just \d{4}-\d{2}-\d{2}. */
function isRealDate(value: string): boolean {
  const parsed = new Date(`${value}T00:00:00Z`);
  return (
    !Number.isNaN(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value
  );
}

export async function canonicalizeMileContext(
  targetId: string,
  context: HypeContext,
): Promise<HypeContext> {
  if (context.contextType !== "mile") return context;
  const composite = MILE_COMPOSITE_RE.exec(context.contextId);
  if (composite) {
    // Shape-valid but impossible dates ('9999-99-99') would blow up the
    // ::date casts downstream — treat them as invalid context.
    if (!isRealDate(composite[1])) {
      throw new Error("invalid_mile_context");
    }
    return { ...context, contextId: `${targetId}:${composite[1]}` };
  }
  const rows = await db.query<{ local_date: string }>(
    `SELECT local_date::text AS local_date FROM workouts
		WHERE workout_id = $1 AND user_id = $2`,
    [context.contextId, targetId],
  );
  const localDate = rows[0]?.local_date;
  if (!localDate) return context;
  return { ...context, contextId: `${targetId}:${localDate}` };
}

/**
 * Dedupe check for 'mile' contexts. Since migration 0012 collapsed legacy
 * workout_id-keyed rows onto the canonical composite, an exact-key check is
 * sufficient — kept as its own entry point in case mile keys grow rules again.
 */
export async function hasHypedMile(
  senderId: string,
  targetId: string,
  contextId: string,
): Promise<boolean> {
  return hasHypedContext(senderId, targetId, "mile", contextId);
}

/**
 * Returns true if the sender has already hyped this exact context.
 * Only meaningful when context is provided; legacy NULL-context hypes are not deduped.
 */
export async function hasHypedContext(
  senderId: string,
  targetId: string,
  contextType: string,
  contextId: string,
): Promise<boolean> {
  const rows = await db.query<{ exists: boolean }>(
    `SELECT EXISTS (
			SELECT 1 FROM hype_log
			WHERE sender_id = $1 AND target_id = $2
				AND context_type = $3 AND context_id = $4
		) AS exists`,
    [senderId, targetId, contextType, contextId],
  );
  return rows[0]?.exists === true;
}

/**
 * ISO timestamp when the sender's daily cap resets — midnight ET tomorrow.
 * Returns null if they have spare capacity right now.
 */
export async function getHypeResetsAt(
  senderId: string,
): Promise<string | null> {
  if (await hasUnlimitedHypes(senderId)) return null;
  const count = await getDailyHypeCount(senderId);
  if (count < HYPE_DAILY_LIMIT) return null;

  const rows = await db.query<{ resets_at: string }>(
    `SELECT ${START_OF_TOMORROW_ET_SQL}::text AS resets_at`,
  );
  return rows[0]?.resets_at ?? null;
}
