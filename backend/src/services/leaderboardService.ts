import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

/**
 * Leaderboard metric options. `miles_ran` (period-scoped, running workouts only)
 * is the default; `miles_total` is the same aggregation but includes walks +
 * runs; `pace` ranks users by fastest mile in the period (ascending — lower is
 * better); `streak` reads the precomputed users.current_streak column.
 */
export type LeaderboardMetric = 'miles_ran' | 'miles_total' | 'pace' | 'streak';
export type LeaderboardPeriod = 'today' | 'week' | 'month' | 'year' | 'all';

export interface LeaderboardEntry {
	rank: number;
	user_id: string;
	username: string | null;
	first_name: string | null;
	last_name: string | null;
	profile_image_url: string | null;
	value: number;
	/** Total miles within the active period (or all-time when metric=streak). */
	period_miles: number;
	/** Fastest mile pace (seconds/mi) within the same window; null if none. */
	period_best_pace: number | null;
	is_current_user: boolean;
}

export interface LeaderboardPage {
	entries: LeaderboardEntry[];
	total_count: number;
	has_more: boolean;
	current_user_entry: LeaderboardEntry | null;
}

interface LeaderboardArgs {
	metric: LeaderboardMetric;
	period: LeaderboardPeriod;
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
 * caller should omit the date WHERE clause entirely. 'today' = just today,
 * 'week' = the current Sunday–Saturday calendar week (UTC; so today if today
 * is Sunday), 'month' = trailing 30 days, 'year' = trailing 365.
 */
function periodStartDate(period: LeaderboardPeriod): string | null {
	if (period === 'all') return null;
	const d = new Date();
	if (period === 'week') {
		// getUTCDay(): 0=Sun..6=Sat — back up to most recent Sunday.
		d.setUTCDate(d.getUTCDate() - d.getUTCDay());
		return d.toISOString().slice(0, 10);
	}
	const days = period === 'today' ? 1 : period === 'month' ? 30 : 365;
	d.setUTCDate(d.getUTCDate() - (days - 1));
	return d.toISOString().slice(0, 10);
}

/**
 * The user IDs eligible for ranking — viewer's accepted friends plus the
 * viewer themselves so they always see their own rank in the list.
 */
async function rankingUserIds(userId: string): Promise<string[]> {
	const rows = await db.query(
		`SELECT friend_id FROM friendships
		 WHERE user_id = $1 AND status = 'accepted'`,
		[userId]
	);
	const ids = rows.map((r: any) => r.friend_id as string);
	ids.push(userId);
	return ids;
}

/**
 * Streak leaderboard reads precomputed users.current_streak (maintained by
 * workoutController after each upload). Zero-streak users excluded.
 */
async function getStreakLeaderboard(args: LeaderboardArgs): Promise<LeaderboardPage> {
	const { userId, limit, offset } = args;
	const ids = await rankingUserIds(userId);

	const countQuery = `
		SELECT COUNT(*)::int AS total
		FROM users u
		WHERE u.current_streak > 0
		  AND u.user_id = ANY($1::text[])
	`;
	const totalRow = await db.query(countQuery, [ids]);
	const total_count: number = totalRow[0]?.total ?? 0;

	// Streak path is always all-time (controller forces period to 'all'), so the
	// attached miles/best-pace stats are also all-time — no date filter.
	const pageQuery = `
		SELECT
			u.user_id,
			u.username,
			u.first_name,
			u.last_name,
			u.profile_image_url,
			u.current_streak::int AS value,
			COALESCE((
				SELECT SUM(w.distance)::float
				FROM workouts w
				WHERE w.user_id = u.user_id
			), 0)::float AS period_miles,
			(
				SELECT MIN(ws.split_pace)::float
				FROM workout_splits ws
				JOIN workouts w ON w.workout_id = ws.workout_id
				WHERE w.user_id = u.user_id
				  AND ws.split_distance >= 0.999
				  AND ws.split_pace > 0
			) AS period_best_pace,
			RANK() OVER (ORDER BY u.current_streak DESC)::int AS rank
		FROM users u
		WHERE u.current_streak > 0
		  AND u.user_id = ANY($1::text[])
		ORDER BY u.current_streak DESC, u.user_id ASC
		LIMIT $2 OFFSET $3
	`;
	const pageRows = await db.query(pageQuery, [ids, limit, offset]);

	const entries: LeaderboardEntry[] = pageRows.map((r: any) => ({
		rank: r.rank,
		user_id: r.user_id,
		username: r.username ?? null,
		first_name: r.first_name ?? null,
		last_name: r.last_name ?? null,
		profile_image_url: r.profile_image_url ?? null,
		value: Number(r.value) || 0,
		period_miles: Number(r.period_miles) || 0,
		period_best_pace: r.period_best_pace != null ? Number(r.period_best_pace) : null,
		is_current_user: r.user_id === userId
	}));

	const current_user_entry = await getCurrentUserStreakEntry(userId, ids, entries);

	return {
		entries,
		total_count,
		has_more: offset + entries.length < total_count,
		current_user_entry
	};
}

async function getCurrentUserStreakEntry(
	userId: string,
	ids: string[],
	pageEntries: LeaderboardEntry[]
): Promise<LeaderboardEntry | null> {
	const inPage = pageEntries.find(e => e.is_current_user);
	if (inPage) return inPage;

	const rows = await db.query(
		`
		SELECT
			u.user_id,
			u.username,
			u.first_name,
			u.last_name,
			u.profile_image_url,
			u.current_streak::int AS value,
			COALESCE((
				SELECT SUM(w.distance)::float
				FROM workouts w
				WHERE w.user_id = u.user_id
			), 0)::float AS period_miles,
			(
				SELECT MIN(ws.split_pace)::float
				FROM workout_splits ws
				JOIN workouts w ON w.workout_id = ws.workout_id
				WHERE w.user_id = u.user_id
				  AND ws.split_distance >= 0.999
				  AND ws.split_pace > 0
			) AS period_best_pace,
			(
				SELECT COUNT(*)::int FROM users u2
				WHERE u2.current_streak > u.current_streak
				  AND u2.user_id = ANY($2::text[])
			) + 1 AS rank
		FROM users u
		WHERE u.user_id = $1
		`,
		[userId, ids]
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
		period_miles: Number(row.period_miles) || 0,
		period_best_pace: row.period_best_pace != null ? Number(row.period_best_pace) : null,
		is_current_user: true
	};
}

/**
 * Miles leaderboard aggregates workouts on the fly across the viewer's
 * friend group. Index `idx_workouts_local_date_user_id` keeps period-windowed
 * queries fast.
 */
async function getMilesLeaderboard(args: LeaderboardArgs): Promise<LeaderboardPage> {
	const { metric, period, userId, limit, offset } = args;
	const startDate = periodStartDate(period);
	const ids = await rankingUserIds(userId);
	// miles_ran counts running workouts only; miles_total counts runs + walks
	// (explicit IN list — guards against any future workout_type values being
	// folded in by accident). The sub-line best-pace stays unfiltered so it
	// matches the user's fastest-mile PR shown elsewhere.
	const runOnly = metric === 'miles_ran';
	const runOrWalk = metric === 'miles_total';

	const params: any[] = [ids];
	const wheres: string[] = [`w.user_id = ANY($1::text[])`];
	if (runOnly) wheres.push(`w.workout_type = 'running'`);
	else if (runOrWalk) wheres.push(`w.workout_type IN ('running', 'walking')`);
	let dateParamIndex: number | null = null;
	if (startDate) {
		params.push(startDate);
		dateParamIndex = params.length;
		wheres.push(`w.local_date >= $${dateParamIndex}`);
	}
	const whereSql = `WHERE ${wheres.join(' AND ')}`;
	const bestPaceDateClause = dateParamIndex !== null ? `AND w.local_date >= $${dateParamIndex}` : '';

	const countQuery = `
		SELECT COUNT(*)::int AS total FROM (
			SELECT w.user_id FROM workouts w
			${whereSql}
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
			FROM workouts w
			${whereSql}
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
			t.value AS period_miles,
			(
				SELECT MIN(ws.split_pace)::float
				FROM workout_splits ws
				JOIN workouts w ON w.workout_id = ws.workout_id
				WHERE w.user_id = u.user_id
				  AND ws.split_distance >= 0.999
				  AND ws.split_pace > 0
				  ${bestPaceDateClause}
			) AS period_best_pace,
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
		period_miles: Number(r.period_miles) || 0,
		period_best_pace: r.period_best_pace != null ? Number(r.period_best_pace) : null,
		is_current_user: r.user_id === userId
	}));

	const current_user_entry = await getCurrentUserMilesEntry(userId, ids, startDate, runOnly, runOrWalk, entries);

	return {
		entries,
		total_count,
		has_more: offset + entries.length < total_count,
		current_user_entry
	};
}

async function getCurrentUserMilesEntry(
	userId: string,
	ids: string[],
	startDate: string | null,
	runOnly: boolean,
	runOrWalk: boolean,
	pageEntries: LeaderboardEntry[]
): Promise<LeaderboardEntry | null> {
	const inPage = pageEntries.find(e => e.is_current_user);
	if (inPage) return inPage;

	const params: any[] = [userId];
	const wheres: string[] = [`w.user_id = $1`];
	if (runOnly) wheres.push(`w.workout_type = 'running'`);
	else if (runOrWalk) wheres.push(`w.workout_type IN ('running', 'walking')`);
	if (startDate) {
		params.push(startDate);
		wheres.push(`w.local_date >= $${params.length}`);
	}
	const myTotalQuery = `
		SELECT COALESCE(SUM(w.distance), 0)::float AS value
		FROM workouts w
		WHERE ${wheres.join(' AND ')}
	`;
	const myTotalRow = await db.query(myTotalQuery, params);
	const myValue: number = Number(myTotalRow[0]?.value ?? 0);
	if (myValue <= 0) return null;

	// Rank = 1 + count of friends-or-self whose period total exceeds mine.
	const rankParams: any[] = [myValue, ids];
	const rankInnerWheres: string[] = [`w.user_id = ANY($2::text[])`];
	if (runOnly) rankInnerWheres.push(`w.workout_type = 'running'`);
	else if (runOrWalk) rankInnerWheres.push(`w.workout_type IN ('running', 'walking')`);
	if (startDate) {
		rankParams.push(startDate);
		rankInnerWheres.push(`w.local_date >= $${rankParams.length}`);
	}

	const rankQuery = `
		SELECT COUNT(*)::int + 1 AS rank FROM (
			SELECT w.user_id
			FROM workouts w
			WHERE ${rankInnerWheres.join(' AND ')}
			GROUP BY w.user_id
			HAVING SUM(w.distance) > $1
		) t
	`;
	const rankRow = await db.query(rankQuery, rankParams);
	const rank: number = rankRow[0]?.rank ?? 1;

	const userRow = await db.query(
		`SELECT user_id, username, first_name, last_name, profile_image_url FROM users WHERE user_id = $1`,
		[userId]
	);
	const u = userRow[0];
	if (!u) return null;

	// Best mile pace within the same period (or all-time when startDate is null).
	const paceParams: any[] = [userId];
	const paceWheres: string[] = [`w.user_id = $1`, `ws.split_distance >= 0.999`, `ws.split_pace > 0`];
	if (startDate) {
		paceParams.push(startDate);
		paceWheres.push(`w.local_date >= $${paceParams.length}`);
	}
	const paceRow = await db.query(
		`SELECT MIN(ws.split_pace)::float AS best_pace
		 FROM workout_splits ws
		 JOIN workouts w ON w.workout_id = ws.workout_id
		 WHERE ${paceWheres.join(' AND ')}`,
		paceParams
	);
	const bestPace = paceRow[0]?.best_pace;

	return {
		rank,
		user_id: u.user_id,
		username: u.username ?? null,
		first_name: u.first_name ?? null,
		last_name: u.last_name ?? null,
		profile_image_url: u.profile_image_url ?? null,
		value: myValue,
		period_miles: myValue,
		period_best_pace: bestPace != null ? Number(bestPace) : null,
		is_current_user: true
	};
}

export async function getLeaderboard(args: LeaderboardArgs): Promise<LeaderboardPage> {
	switch (args.metric) {
		case 'streak':
			return getStreakLeaderboard(args);
		case 'pace':
			return getPaceLeaderboard(args);
		case 'miles_total':
		case 'miles_ran':
		default:
			return getMilesLeaderboard(args);
	}
}

/**
 * Pace leaderboard: ranks users by their fastest *completed* mile split in
 * the active period. The 0.999 distance floor (vs the legacy 0.95 used by
 * badges / dailyChallenge) excludes the trailing partial split that
 * SplitCalculator emits with an extrapolated per-mile pace — otherwise
 * someone who only ran half a mile at "7:00/mi pace" would show up.
 */
async function getPaceLeaderboard(args: LeaderboardArgs): Promise<LeaderboardPage> {
	const { period, userId, limit, offset } = args;
	const startDate = periodStartDate(period);
	const ids = await rankingUserIds(userId);

	const params: any[] = [ids];
	const wheres: string[] = [`w.user_id = ANY($1::text[])`, `ws.split_distance >= 0.999`, `ws.split_pace > 0`];
	let dateParamIndex: number | null = null;
	if (startDate) {
		params.push(startDate);
		dateParamIndex = params.length;
		wheres.push(`w.local_date >= $${dateParamIndex}`);
	}
	const whereSql = `WHERE ${wheres.join(' AND ')}`;
	const milesDateClause = dateParamIndex !== null ? `AND w.local_date >= $${dateParamIndex}` : '';

	const countQuery = `
		SELECT COUNT(*)::int AS total FROM (
			SELECT w.user_id
			FROM workout_splits ws
			JOIN workouts w ON w.workout_id = ws.workout_id
			${whereSql}
			GROUP BY w.user_id
		) t
	`;
	const totalRow = await db.query(countQuery, params);
	const total_count: number = totalRow[0]?.total ?? 0;

	params.push(limit);
	const limitParamIndex = params.length;
	params.push(offset);
	const offsetParamIndex = params.length;

	const pageQuery = `
		WITH bests AS (
			SELECT w.user_id, MIN(ws.split_pace)::float AS value
			FROM workout_splits ws
			JOIN workouts w ON w.workout_id = ws.workout_id
			${whereSql}
			GROUP BY w.user_id
		)
		SELECT
			u.user_id,
			u.username,
			u.first_name,
			u.last_name,
			u.profile_image_url,
			b.value,
			COALESCE((
				SELECT SUM(w.distance)::float
				FROM workouts w
				WHERE w.user_id = u.user_id
				  ${milesDateClause}
			), 0)::float AS period_miles,
			b.value AS period_best_pace,
			RANK() OVER (ORDER BY b.value ASC)::int AS rank
		FROM bests b
		JOIN users u ON u.user_id = b.user_id
		ORDER BY b.value ASC, u.user_id ASC
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
		period_miles: Number(r.period_miles) || 0,
		period_best_pace: r.period_best_pace != null ? Number(r.period_best_pace) : null,
		is_current_user: r.user_id === userId
	}));

	const current_user_entry = await getCurrentUserPaceEntry(userId, ids, startDate, entries);

	return {
		entries,
		total_count,
		has_more: offset + entries.length < total_count,
		current_user_entry
	};
}

async function getCurrentUserPaceEntry(
	userId: string,
	ids: string[],
	startDate: string | null,
	pageEntries: LeaderboardEntry[]
): Promise<LeaderboardEntry | null> {
	const inPage = pageEntries.find(e => e.is_current_user);
	if (inPage) return inPage;

	// Viewer's best pace in the window.
	const myParams: any[] = [userId];
	const myWheres: string[] = [`w.user_id = $1`, `ws.split_distance >= 0.999`, `ws.split_pace > 0`];
	if (startDate) {
		myParams.push(startDate);
		myWheres.push(`w.local_date >= $${myParams.length}`);
	}
	const myRow = await db.query(
		`SELECT MIN(ws.split_pace)::float AS value
		 FROM workout_splits ws
		 JOIN workouts w ON w.workout_id = ws.workout_id
		 WHERE ${myWheres.join(' AND ')}`,
		myParams
	);
	const myValue: number | null = myRow[0]?.value != null ? Number(myRow[0].value) : null;
	if (myValue == null || !(myValue > 0)) return null;

	// Rank = 1 + count of friends-or-self whose best pace is strictly lower
	// (faster). RANK semantics with ties match getPaceLeaderboard.
	const rankParams: any[] = [myValue, ids];
	const rankWheres: string[] = [`w.user_id = ANY($2::text[])`, `ws.split_distance >= 0.999`, `ws.split_pace > 0`];
	if (startDate) {
		rankParams.push(startDate);
		rankWheres.push(`w.local_date >= $${rankParams.length}`);
	}
	const rankRow = await db.query(
		`SELECT COUNT(*)::int + 1 AS rank FROM (
			SELECT w.user_id
			FROM workout_splits ws
			JOIN workouts w ON w.workout_id = ws.workout_id
			WHERE ${rankWheres.join(' AND ')}
			GROUP BY w.user_id
			HAVING MIN(ws.split_pace) < $1
		) t`,
		rankParams
	);
	const rank: number = rankRow[0]?.rank ?? 1;

	// Period miles for the sub-line.
	const milesParams: any[] = [userId];
	const milesWheres: string[] = [`w.user_id = $1`];
	if (startDate) {
		milesParams.push(startDate);
		milesWheres.push(`w.local_date >= $${milesParams.length}`);
	}
	const milesRow = await db.query(
		`SELECT COALESCE(SUM(w.distance), 0)::float AS miles
		 FROM workouts w
		 WHERE ${milesWheres.join(' AND ')}`,
		milesParams
	);
	const periodMiles: number = Number(milesRow[0]?.miles ?? 0);

	const userRow = await db.query(
		`SELECT user_id, username, first_name, last_name, profile_image_url FROM users WHERE user_id = $1`,
		[userId]
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
		period_miles: periodMiles,
		period_best_pace: myValue,
		is_current_user: true
	};
}

/**
 * Recompute a single user's current streak and write it to users.current_streak.
 * Called by the workout upload pipeline so the streak leaderboard stays fresh
 * without a cron job. Mirrors the qualifying-day rule from getActiveStreak:
 * a day qualifies when SUM(distance) >= 0.95 mi, counting consecutive
 * qualifying days back from today (or yesterday if today has no workouts yet).
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
		[userId]
	);
	const userToday: string = todayRow[0]?.user_today;
	if (!userToday) {
		await db.query(`UPDATE users SET current_streak = 0 WHERE user_id = $1`, [userId]);
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
		[userId]
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

	await db.query(`UPDATE users SET current_streak = $1 WHERE user_id = $2`, [streak, userId]);
	return streak;
}

function dateStringMinus(dateStr: string, days: number): string {
	const [y, m, d] = dateStr.split('-').map(Number);
	const date = new Date(Date.UTC(y, m - 1, d));
	date.setUTCDate(date.getUTCDate() - days);
	return date.toISOString().slice(0, 10);
}
