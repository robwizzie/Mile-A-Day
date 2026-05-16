import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

export type LeaderboardMetric = "miles" | "streak";
export type LeaderboardPeriod = "week" | "month" | "year" | "all";
export type LeaderboardScope = "global" | "friends";

export interface LeaderboardEntry {
  rank: number;
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  value: number;
  is_current_user: boolean;
}

export interface LeaderboardPage {
  entries: LeaderboardEntry[];
  total_count: number;
  has_more: boolean;
  current_user_entry: LeaderboardEntry | null;
  /** True if the viewer has opted out — UI uses this to render a "you're
   *  hidden" banner with a one-tap re-enable. Opted-out users still receive
   *  rankings of others; only their own row is suppressed. */
  viewer_opted_out: boolean;
}

interface LeaderboardArgs {
  metric: LeaderboardMetric;
  period: LeaderboardPeriod;
  scope: LeaderboardScope;
  userId: string;
  limit: number;
  offset: number;
}

const MAX_LIMIT = 50;
const DEFAULT_LIMIT = 25;

export function clampLimit(raw: number | undefined): number {
  if (!raw || !Number.isFinite(raw) || raw <= 0) return DEFAULT_LIMIT;
  return Math.min(Math.floor(raw), MAX_LIMIT);
}

export function clampOffset(raw: number | undefined): number {
  if (!raw || !Number.isFinite(raw) || raw < 0) return 0;
  return Math.floor(raw);
}

/**
 * Start date (inclusive, ISO date string) for a period. `all` returns null —
 * caller should omit the date WHERE clause entirely.
 *
 * Periods are rolling windows ending today: 'week' = last 7 days, 'month' =
 * last 30, 'year' = last 365. Using rolling windows rather than calendar
 * boundaries keeps the "best of the week" leaderboard stable through midnight
 * Sunday→Monday rollovers.
 */
function periodStartDate(period: LeaderboardPeriod): string | null {
  if (period === "all") return null;
  const days = period === "week" ? 7 : period === "month" ? 30 : 365;
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - (days - 1));
  return d.toISOString().slice(0, 10);
}

/**
 * The user IDs eligible for ranking when scope=friends. Includes the viewer
 * themselves so they can see their own rank alongside friends.
 */
async function friendsIdList(userId: string): Promise<string[]> {
  const rows = await db.query(
    `SELECT friend_id FROM friendships
		 WHERE user_id = $1 AND status = 'accepted'`,
    [userId],
  );
  const ids = rows.map((r: any) => r.friend_id as string);
  ids.push(userId);
  return ids;
}

/** Reads the viewer's leaderboard_opt_out flag. Defaults to false if the row
 *  is missing for any reason. Cheap single-key lookup. */
async function isViewerOptedOut(userId: string): Promise<boolean> {
  const rows = await db.query(
    `SELECT leaderboard_opt_out FROM users WHERE user_id = $1`,
    [userId],
  );
  return Boolean(rows[0]?.leaderboard_opt_out);
}

export async function setLeaderboardOptOut(
  userId: string,
  optOut: boolean,
): Promise<boolean> {
  const rows = await db.query(
    `UPDATE users
		 SET leaderboard_opt_out = $2
		 WHERE user_id = $1
		 RETURNING leaderboard_opt_out`,
    [userId, optOut],
  );
  return Boolean(rows[0]?.leaderboard_opt_out);
}

/**
 * Streak leaderboard reads the precomputed users.current_streak column (kept
 * fresh by workoutController after each upload). Zero-streak users are
 * excluded so the list shows only people with an active streak.
 */
async function getStreakLeaderboard(
  args: LeaderboardArgs,
): Promise<LeaderboardPage> {
  const { scope, userId, limit, offset } = args;

  const scopeClause =
    scope === "friends" ? `AND u.user_id = ANY($1::text[])` : "";
  const scopeParams: any[] =
    scope === "friends" ? [await friendsIdList(userId)] : [];

  const countQuery = `
		SELECT COUNT(*)::int AS total
		FROM users u
		WHERE u.current_streak > 0
		  AND u.leaderboard_opt_out = FALSE
		${scopeClause}
	`;
  const totalRow = await db.query(countQuery, scopeParams);
  const total_count: number = totalRow[0]?.total ?? 0;

  const pageQuery = `
		SELECT
			u.user_id,
			u.username,
			u.first_name,
			u.last_name,
			u.profile_image_url,
			u.current_streak::int AS value,
			RANK() OVER (ORDER BY u.current_streak DESC)::int AS rank
		FROM users u
		WHERE u.current_streak > 0
		  AND u.leaderboard_opt_out = FALSE
		${scopeClause}
		ORDER BY u.current_streak DESC, u.user_id ASC
		LIMIT $${scopeParams.length + 1} OFFSET $${scopeParams.length + 2}
	`;
  const pageRows = await db.query(pageQuery, [...scopeParams, limit, offset]);

  const entries: LeaderboardEntry[] = pageRows.map((r: any) => ({
    rank: r.rank,
    user_id: r.user_id,
    username: r.username ?? null,
    first_name: r.first_name ?? null,
    last_name: r.last_name ?? null,
    profile_image_url: r.profile_image_url ?? null,
    value: Number(r.value) || 0,
    is_current_user: r.user_id === userId,
  }));

  const current_user_entry = await getCurrentUserStreakEntry(
    userId,
    scope,
    entries,
  );

  return {
    entries,
    total_count,
    has_more: offset + entries.length < total_count,
    current_user_entry,
    viewer_opted_out: false,
  };
}

async function getCurrentUserStreakEntry(
  userId: string,
  scope: LeaderboardScope,
  pageEntries: LeaderboardEntry[],
): Promise<LeaderboardEntry | null> {
  const inPage = pageEntries.find((e) => e.is_current_user);
  if (inPage) return inPage;

  const scopeClause =
    scope === "friends" ? `AND u.user_id = ANY($2::text[])` : "";
  const scopeParams: any[] =
    scope === "friends" ? [await friendsIdList(userId)] : [];

  const rows = await db.query(
    `
		SELECT
			u.user_id,
			u.username,
			u.first_name,
			u.last_name,
			u.profile_image_url,
			u.current_streak::int AS value,
			(
				SELECT COUNT(*)::int FROM users u2
				WHERE u2.current_streak > u.current_streak
				  AND u2.leaderboard_opt_out = FALSE
				${scope === "friends" ? `AND u2.user_id = ANY($2::text[])` : ""}
			) + 1 AS rank
		FROM users u
		WHERE u.user_id = $1
		  AND u.leaderboard_opt_out = FALSE
		`,
    [userId, ...scopeParams],
  );

  const row = rows[0];
  if (!row || row.value <= 0) return null;
  return {
    rank: row.rank,
    user_id: row.user_id,
    username: row.username ?? null,
    first_name: row.first_name ?? null,
    last_name: row.last_name ?? null,
    profile_image_url: row.profile_image_url ?? null,
    value: Number(row.value) || 0,
    is_current_user: true,
  };
}

/**
 * Miles leaderboard aggregates the workouts table on the fly. The new
 * idx_workouts_local_date_user_id index keeps period-windowed queries fast;
 * 'all' is uncovered and will slow as the table grows — we'll add a
 * precomputed total when that becomes a real problem.
 */
async function getMilesLeaderboard(
  args: LeaderboardArgs,
): Promise<LeaderboardPage> {
  const { scope, period, userId, limit, offset } = args;
  const startDate = periodStartDate(period);

  const params: any[] = [];
  const wheres: string[] = [];

  if (scope === "friends") {
    params.push(await friendsIdList(userId));
    wheres.push(`w.user_id = ANY($${params.length}::text[])`);
  }
  if (startDate) {
    params.push(startDate);
    wheres.push(`w.local_date >= $${params.length}`);
  }
  const whereSql = wheres.length ? `WHERE ${wheres.join(" AND ")}` : "";

  // Filter opted-out users at the CTE level so we don't even SUM their
  // distances. Adds a JOIN to users that piggybacks on the FK index.
  const optOutClause = `u.leaderboard_opt_out = FALSE`;
  const aggregatedFromSql = `
		FROM workouts w
		JOIN users u ON u.user_id = w.user_id
		${wheres.length ? `WHERE ${optOutClause} AND ${wheres.join(" AND ")}` : `WHERE ${optOutClause}`}
	`;

  const countQuery = `
		SELECT COUNT(*)::int AS total FROM (
			SELECT w.user_id
			${aggregatedFromSql}
			GROUP BY w.user_id
			HAVING SUM(w.distance) > 0
		) t
	`;
  const totalRow = await db.query(countQuery, params);
  const total_count: number = totalRow[0]?.total ?? 0;

  params.push(limit);
  const limitParamIndex = params.length;
  params.push(offset);
  const offsetParamIndex = params.length;

  const pageQuery = `
		WITH totals AS (
			SELECT w.user_id, SUM(w.distance)::float AS value
			${aggregatedFromSql}
			GROUP BY w.user_id
			HAVING SUM(w.distance) > 0
		)
		SELECT
			u.user_id,
			u.username,
			u.first_name,
			u.last_name,
			u.profile_image_url,
			t.value,
			RANK() OVER (ORDER BY t.value DESC)::int AS rank
		FROM totals t
		JOIN users u ON u.user_id = t.user_id
		ORDER BY t.value DESC, u.user_id ASC
		LIMIT $${limitParamIndex} OFFSET $${offsetParamIndex}
	`;
  const pageRows = await db.query(pageQuery, params);

  const entries: LeaderboardEntry[] = pageRows.map((r: any) => ({
    rank: r.rank,
    user_id: r.user_id,
    username: r.username ?? null,
    first_name: r.first_name ?? null,
    last_name: r.last_name ?? null,
    profile_image_url: r.profile_image_url ?? null,
    value: Number(r.value) || 0,
    is_current_user: r.user_id === userId,
  }));

  const current_user_entry = await getCurrentUserMilesEntry(
    userId,
    scope,
    startDate,
    entries,
  );

  return {
    entries,
    total_count,
    has_more: offset + entries.length < total_count,
    current_user_entry,
    viewer_opted_out: false,
  };
}

async function getCurrentUserMilesEntry(
  userId: string,
  scope: LeaderboardScope,
  startDate: string | null,
  pageEntries: LeaderboardEntry[],
): Promise<LeaderboardEntry | null> {
  const inPage = pageEntries.find((e) => e.is_current_user);
  if (inPage) return inPage;

  const params: any[] = [userId];
  const wheres: string[] = [`w.user_id = $1`];
  if (startDate) {
    params.push(startDate);
    wheres.push(`w.local_date >= $${params.length}`);
  }
  const myTotalQuery = `
		SELECT COALESCE(SUM(w.distance), 0)::float AS value
		FROM workouts w
		WHERE ${wheres.join(" AND ")}
	`;
  const myTotalRow = await db.query(myTotalQuery, params);
  const myValue: number = Number(myTotalRow[0]?.value ?? 0);
  if (myValue <= 0) return null;

  // Rank = 1 + count of (non-opted-out) users whose period total exceeds mine.
  const rankParams: any[] = [myValue];
  const rankWheres: string[] = [`SUM(w.distance) > $1`];
  const rankInnerWheres: string[] = [`u.leaderboard_opt_out = FALSE`];
  if (scope === "friends") {
    rankParams.push(await friendsIdList(userId));
    rankInnerWheres.push(`w.user_id = ANY($${rankParams.length}::text[])`);
  }
  if (startDate) {
    rankParams.push(startDate);
    rankInnerWheres.push(`w.local_date >= $${rankParams.length}`);
  }

  const rankQuery = `
		SELECT COUNT(*)::int + 1 AS rank FROM (
			SELECT w.user_id
			FROM workouts w
			JOIN users u ON u.user_id = w.user_id
			WHERE ${rankInnerWheres.join(" AND ")}
			GROUP BY w.user_id
			HAVING ${rankWheres.join(" AND ")}
		) t
	`;
  const rankRow = await db.query(rankQuery, rankParams);
  const rank: number = rankRow[0]?.rank ?? 1;

  const userRow = await db.query(
    `SELECT user_id, username, first_name, last_name, profile_image_url FROM users WHERE user_id = $1`,
    [userId],
  );
  const u = userRow[0];
  if (!u) return null;

  return {
    rank,
    user_id: u.user_id,
    username: u.username ?? null,
    first_name: u.first_name ?? null,
    last_name: u.last_name ?? null,
    profile_image_url: u.profile_image_url ?? null,
    value: myValue,
    is_current_user: true,
  };
}

export async function getLeaderboard(
  args: LeaderboardArgs,
): Promise<LeaderboardPage> {
  const [page, viewerOptedOut] = await Promise.all([
    args.metric === "streak"
      ? getStreakLeaderboard(args)
      : getMilesLeaderboard(args),
    isViewerOptedOut(args.userId),
  ]);

  // When opted out the viewer's row is already excluded from queries —
  // surface the flag so the UI can render the "you're hidden" banner.
  return {
    ...page,
    current_user_entry: viewerOptedOut ? null : page.current_user_entry,
    viewer_opted_out: viewerOptedOut,
  };
}

/**
 * Recompute a single user's current streak and write it to users.current_streak.
 * Called by the workout upload pipeline so the streak leaderboard stays fresh
 * without a cron job. Mirrors the qualifying-day rule from getActiveStreak —
 * a day qualifies when SUM(distance) >= 0.95 mi, and the streak counts back
 * from today (or yesterday, if today has no qualifying workouts yet).
 */
export async function refreshCurrentStreak(userId: string): Promise<number> {
  const todayRow = await db.query(
    `
		SELECT to_char(
		  (NOW() + (COALESCE(
		    (SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
		    0
		  ) || ' minutes')::interval)::date,
		  'YYYY-MM-DD'
		) AS user_today
		`,
    [userId],
  );
  const userToday: string = todayRow[0]?.user_today;
  if (!userToday) {
    await db.query(`UPDATE users SET current_streak = 0 WHERE user_id = $1`, [
      userId,
    ]);
    return 0;
  }

  const days = await db.query(
    `
		SELECT to_char(local_date, 'YYYY-MM-DD') AS local_date
		FROM workouts
		WHERE user_id = $1
		GROUP BY local_date
		HAVING SUM(distance) >= 0.95
		ORDER BY local_date DESC
		LIMIT 500
		`,
    [userId],
  );

  let streak = 0;
  let expected: string | undefined;
  const yesterday = dateStringMinus(userToday, 1);

  for (const row of days) {
    const date: string = row.local_date;
    if (expected === undefined) {
      if (date !== userToday && date !== yesterday) {
        streak = 0;
        break;
      }
      streak = 1;
      expected = dateStringMinus(date, 1);
    } else if (date === expected) {
      streak++;
      expected = dateStringMinus(date, 1);
    } else {
      break;
    }
  }

  await db.query(`UPDATE users SET current_streak = $1 WHERE user_id = $2`, [
    streak,
    userId,
  ]);
  return streak;
}

function dateStringMinus(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}
