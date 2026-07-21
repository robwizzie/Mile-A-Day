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
 * Everyone who hyped one specific context, newest first — powers the
 * Instagram-style "who liked this" list behind the hype tally. DISTINCT ON
 * sender so one person appears once, matching COUNT(DISTINCT sender_id).
 *
 * 'mile' and 'post' contexts use the unified RUN rule (see runHypeMatchSql):
 * hypes on a run's mile composite AND on any live post linked to that run's
 * workout are one pool, so this list always matches the tallies the feed,
 * friends list, and inbox show for the same run.
 */
export async function getContextHypers(
  targetId: string,
  contextType: string,
  contextId: string,
  limit: number = 100,
): Promise<ContextHyper[]> {
  let matchSql: string;
  const params: unknown[] = [targetId, contextId, limit];

  if (contextType === "mile") {
    // $2 = a workout id from the feed, or a legacy/user-notification
    // user:local_date composite. Match both exact workout hypes and legacy
    // composite hypes that belong to the same workout day.
    matchSql = `(
			(h.context_type = 'mile' AND (
				h.context_id = $2
				OR h.context_id IN (
					SELECT w.user_id || ':' || w.local_date::text
					FROM workouts w
					WHERE w.user_id = $1 AND w.workout_id::text = $2
				)
			))
			OR (h.context_type = 'post' AND h.context_id IN (
				SELECT p.post_id::text
				FROM posts p
				JOIN workouts w ON w.workout_id = p.workout_id
				WHERE p.user_id = $1 AND p.deleted_at IS NULL
					AND (
						w.workout_id::text = $2
						OR (w.user_id || ':' || w.local_date::text) = $2
					)
			))
		)`;
  } else if (contextType === "post") {
    // $2 = post id. Expand through the post's linked workout (when any) to
    // the run's mile hypes and sibling posts.
    matchSql = `EXISTS (
			SELECT 1 FROM posts p
			WHERE p.post_id::text = $2 AND p.user_id = $1
				AND ${postHypeMatchSql("h", "p")}
		)`;
  } else {
    matchSql = `(h.context_type = $4 AND h.context_id = $2)`;
    params.push(contextType);
  }

  const rows = await db.query<ContextHyper>(
    `SELECT h2.sender_id AS user_id, u.username, u.first_name, u.last_name,
			u.profile_image_url, h2.created_at
		FROM (
			SELECT DISTINCT ON (h.sender_id) h.sender_id, h.created_at
			FROM hype_log h
			WHERE h.target_id = $1 AND ${matchSql}
			ORDER BY h.sender_id, h.created_at DESC
		) h2
		JOIN users u ON u.user_id = h2.sender_id
		ORDER BY h2.created_at DESC
		LIMIT $3`,
    params,
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
 * SQL predicate matching a hype_log row (alias `h`) to a RUN identified by a
 * workouts-row alias `w`: the canonical mile composite OR a 'post' hype on any
 * live post linked to that workout. THE tally rule — one run, one number, no
 * matter which surface the hype came from (inbox/friends list send 'mile',
 * feed/profile cards send 'post'). Every surface that counts a run's hypes
 * must use this or `postHypeMatchSql`, or the numbers drift apart.
 */
export function runHypeMatchSql(h: string, w: string): string {
  return `(
		(${h}.context_type = 'mile' AND (${mileHypeKeyMatchSql(h, w)} OR ${h}.context_id = ${w}.workout_id::text))
		OR (${h}.context_type = 'post' AND ${h}.context_id IN (
			SELECT p_.post_id::text FROM posts p_
			WHERE p_.workout_id = ${w}.workout_id AND p_.user_id = ${w}.user_id
				AND p_.deleted_at IS NULL
		))
	)`;
}

/**
 * Viewer/button-state + dedupe predicate for one concrete workout. This is now
 * the SAME rule as the tally (runHypeMatchSql): a run's mile hypes (the day
 * composite the inbox sends AND the exact workout id the feed sends) plus the
 * hypes on any live post linked to it are ONE pool. Hyping a run from any
 * surface therefore marks it hyped on every surface and blocks a second hype —
 * previously this predicate matched the workout id only, so an inbox hype
 * (composite) and a feed hype (workout id) on the SAME run slipped past each
 * other and double-spent. A DIFFERENT same-day workout keyed by its own
 * workout id stays independently hypeable (its id ≠ this run's id/composite).
 */
export function runHypedByViewerMatchSql(h: string, w: string): string {
  return runHypeMatchSql(h, w);
}

/**
 * The post-side counterpart of `runHypeMatchSql`: matches a hype_log row
 * (alias `h`) to a POST row (alias `p`) — the post's own 'post' hypes, plus,
 * when the post is linked to a workout, the run's 'mile' hypes and hypes on
 * sibling posts of the same run. Keeps a feed post card's tally equal to the
 * inbox / friends-list tally for the same run.
 */
export function postHypeMatchSql(h: string, p: string): string {
  return `(
		(${h}.context_type = 'post' AND ${h}.context_id = ${p}.post_id::text)
		OR (${p}.workout_id IS NOT NULL AND ${h}.context_type = 'mile' AND (
			${h}.context_id = ${p}.workout_id::text
			OR ${h}.context_id = (
				SELECT w_.user_id || ':' || w_.local_date::text FROM workouts w_
				WHERE w_.workout_id = ${p}.workout_id
			)
		))
		OR (${p}.workout_id IS NOT NULL AND ${h}.context_type = 'post' AND ${h}.context_id IN (
			SELECT p2_.post_id::text FROM posts p2_
			WHERE p2_.workout_id = ${p}.workout_id AND p2_.user_id = ${p}.user_id
				AND p2_.deleted_at IS NULL
		))
	)`;
}

/**
 * Viewer/button-state + dedupe predicate for "did I hype this card?" — now the
 * SAME rule as the post tally (postHypeMatchSql), so a post card and the run's
 * mile hype (the inbox's day composite OR the feed's workout id) can't both be
 * spent on one run. Previously it matched the workout id only, letting an inbox
 * mile hype (composite) and this post's hype double-count for the same run.
 */
export function postHypedByViewerMatchSql(h: string, p: string): string {
  return postHypeMatchSql(h, p);
}

/**
 * Canonicalize a 'mile' hype context. The notifications inbox keys by
 * `<userId>:<localDate>`; feed workout cards key by exact workout_id so a
 * second same-day workout is still hypeable. A composite id is re-prefixed with
 * the target so a client can't write a key that pollutes another user's counts.
 * Unresolvable ids pass through unchanged for backward compatibility.
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
  return context;
}

/** Exact-key dedupe for older callers that do not need run/post expansion. */
export async function hasHypedMile(
  senderId: string,
  targetId: string,
  contextId: string,
): Promise<boolean> {
  return hasHypedContext(senderId, targetId, "mile", contextId);
}

/**
 * Unified-run dedupe for 'mile' and 'post' contexts: true when the sender has
 * hyped this RUN through EITHER context (the mile composite, or any live post
 * linked to the run's workout). One run = one hype per sender, no matter
 * which surface it's sent from — without this, hyping a mile from the inbox
 * and then the same run's post from the feed double-spends the daily
 * allowance and (pre-unification) double-counted.
 */
export async function hasHypedRunContext(
  senderId: string,
  targetId: string,
  contextType: "mile" | "post",
  contextId: string,
): Promise<boolean> {
  const isCompositeMile =
    contextType === "mile" && MILE_COMPOSITE_RE.test(contextId);
  const matchSql =
    contextType === "mile" && isCompositeMile
      ? `(
			(h.context_type = 'mile' AND (
					h.context_id = $3
					OR h.context_id IN (
						SELECT w.workout_id::text FROM workouts w
						WHERE w.user_id = $2
							AND (w.user_id || ':' || w.local_date::text) = $3
					)
				))
			OR (h.context_type = 'post' AND h.context_id IN (
				SELECT p.post_id::text
				FROM posts p
				JOIN workouts w ON w.workout_id = p.workout_id
				WHERE p.user_id = $2 AND p.deleted_at IS NULL
					AND (w.user_id || ':' || w.local_date::text) = $3
			))
		)`
      : contextType === "mile"
        ? `EXISTS (
			SELECT 1 FROM workouts w
			WHERE w.workout_id::text = $3 AND w.user_id = $2
				AND ${runHypedByViewerMatchSql("h", "w")}
		)`
        : `EXISTS (
			SELECT 1 FROM posts p
			WHERE p.post_id::text = $3 AND p.user_id = $2
				AND ${postHypedByViewerMatchSql("h", "p")}
		)`;

  const rows = await db.query<{ exists: boolean }>(
    `SELECT EXISTS (
			SELECT 1 FROM hype_log h
			WHERE h.sender_id = $1 AND h.target_id = $2 AND ${matchSql}
		) AS exists`,
    [senderId, targetId, contextId],
  );
  return rows[0]?.exists === true;
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
