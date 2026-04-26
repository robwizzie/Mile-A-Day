import { BadRequestError } from '../errors/Errors.js';
import { Competition, CompetitionActivity, CompetitionOptions, CompetitionType, CompetitionUser } from '../types/competitions.js';
import { PostgresService } from './DbService.js';
import { getQuantityDateRange } from './workoutService.js';
import { sendOrQueueCompetitionNotification } from './pushNotificationService.js';

const WORKOUT_TYPE_MAP: Record<string, string> = { run: 'running', walk: 'walking', running: 'running', walking: 'walking' };

const db = PostgresService.getInstance();

const ET_DATE_FORMATTER = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });

export function getTodayET(): string {
	return ET_DATE_FORMATTER.format(new Date());
}

function etDateToUtcMs(dateStr: string): number {
	const [y, m, d] = dateStr.split('-').map(Number);
	const utcGuess = Date.UTC(y, m - 1, d);
	const parts = new Intl.DateTimeFormat('en-US', {
		timeZone: 'America/New_York',
		hourCycle: 'h23',
		year: 'numeric',
		month: '2-digit',
		day: '2-digit',
		hour: '2-digit',
		minute: '2-digit',
		second: '2-digit'
	}).formatToParts(new Date(utcGuess));
	const get = (type: string) => parseInt(parts.find(p => p.type === type)!.value, 10);
	const etAsUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
	const offsetMs = etAsUtc - utcGuess;
	return utcGuess - offsetMs;
}

interface CreateCompetitionParams {
	competition_name: string;
	start_date?: string;
	end_date?: string;
	type: CompetitionType;
	workouts?: CompetitionActivity[];
	options: CompetitionOptions;
	owner: string;
}

export async function createCompetition(params: CreateCompetitionParams) {
	checkKeys(params);

	const { competition_name, start_date, end_date, workouts = ['run', 'walk'], type, options, owner } = params;

	const [competition] = await db.query(
		`INSERT INTO competitions (
            competition_name, start_date, end_date,
            workouts, type, options, owner
        ) VALUES (
			$1, $2, $3, $4, $5, $6, $7
		) RETURNING *;`,
		[competition_name, start_date || null, end_date || null, JSON.stringify(workouts), type, JSON.stringify(options), owner]
	);

	await db.query(
		`INSERT INTO competition_users (
            competition_id, user_id, progress, invite_status
        ) VALUES (
            $1, $2, '{}', 'accepted'
		)`,
		[competition.id, owner]
	);

	return competition.id;
}

function checkKeys(params: CreateCompetitionParams) {
	const { end_date, workouts = ['run', 'walk'], type, options, owner } = params;

	const requiredKeys = [];
	const optionKeys = Object.keys(options);
	const missingKeys: string[] = [];

	if (workouts === undefined || workouts.length === 0) {
		missingKeys.push('workouts');
	}

	if (!owner) {
		missingKeys.push('owner');
	}

	if (type === 'streaks') {
		requiredKeys.push('goal', 'unit', 'interval');

		if (
			end_date === undefined &&
			options.duration_hours === undefined &&
			options.lives === undefined &&
			options.first_to === undefined
		) {
			missingKeys.push('(lives, end_date, or duration_hours)');
		}
	} else if (type === 'apex') {
		requiredKeys.push('unit');

		if (end_date === undefined && options.duration_hours === undefined) {
			missingKeys.push('(end_date or duration_hours)');
		}
	} else if (type === 'clash') {
		requiredKeys.push('unit', 'interval');

		if (end_date === undefined && options.first_to === undefined && options.duration_hours === undefined) {
			missingKeys.push('(first_to, end_date, or duration_hours)');
		}
	} else if (type === 'targets') {
		requiredKeys.push('goal', 'unit', 'interval');

		if (end_date === undefined && options.duration_hours === undefined) {
			missingKeys.push('(end_date or duration_hours)');
		}
	} else if (type === 'race') {
		requiredKeys.push('goal', 'unit');
	}

	requiredKeys.forEach(key => {
		if (!optionKeys.includes(key)) {
			missingKeys.push(key);
		}
	});

	if (missingKeys.length) {
		throw new BadRequestError(`Missing required key(s): ${missingKeys.join(', ')}`);
	}
}

// User-enriched query fragment for competition_users JOIN
const USERS_AGG_SQL = `
	COALESCE(
		jsonb_agg(
			jsonb_build_object(
				'competition_id', cu.competition_id,
				'user_id', cu.user_id,
				'invite_status', cu.invite_status,
				'progress', cu.progress,
				'username', u.username,
				'profile_image_url', u.profile_image_url
			)
		) FILTER (WHERE cu.competition_id IS NOT NULL),
		'[]'::jsonb
	) as users`;

export async function getCompetition(competitionId: string): Promise<Competition> {
	const competition = (
		await db.query(
			`SELECT
				c.*,
				${USERS_AGG_SQL}
			FROM competitions c
			LEFT JOIN competition_users cu ON cu.competition_id = c.id
			LEFT JOIN users u ON u.user_id = cu.user_id
			WHERE c.id = $1
			GROUP BY c.id;`,
			[competitionId]
		)
	)[0];

	if (!competition) {
		return competition;
	}

	// Calculate scores for started competitions (start_date on or before today in ET)
	if (competition.start_date && competition.start_date <= getTodayET()) {
		const userScores = await getUserScores(competition);
		competition.users = competition.users.map((user: CompetitionUser) => ({ ...user, ...userScores[user.user_id] }));
	}

	return competition;
}

export async function getCompetitions(
	userId: string,
	{ page = 1, status = 'active', pageSize = 10 }: { page: number; status: string; pageSize: number }
): Promise<Competition[]> {
	let statusCondition = '';
	const TODAY_ET_SQL = "(NOW() AT TIME ZONE 'America/New_York')::date";

	if (status === 'get_set' || status === 'lobby') {
		statusCondition = `AND (c.start_date IS NULL OR c.start_date > ${TODAY_ET_SQL})`;
	} else if (status === 'go') {
		statusCondition = `AND c.start_date <= ${TODAY_ET_SQL} AND (c.end_date IS NULL OR c.end_date >= ${TODAY_ET_SQL})`;
	} else if (status === 'active') {
		// Lobby + currently running (excludes finished)
		statusCondition = `AND (c.start_date IS NULL OR c.end_date IS NULL OR c.end_date >= ${TODAY_ET_SQL})`;
	} else if (status === 'finished') {
		statusCondition = `AND (c.end_date IS NOT NULL AND c.end_date < ${TODAY_ET_SQL})`;
	}
	// status === 'all' or 'on_your_mark' => no date filter from statusCondition

	const query = `SELECT
			c.*,
			${USERS_AGG_SQL}
		FROM competitions c
		LEFT JOIN competition_users cu ON cu.competition_id = c.id
		LEFT JOIN users u ON u.user_id = cu.user_id
		WHERE c.id IN (
			SELECT competition_id
	  		FROM competition_users
	  		WHERE user_id = $1
			${status === 'on_your_mark' ? "AND invite_status = 'pending'" : "AND invite_status = 'accepted'"}
		)
		${statusCondition}
		GROUP BY c.id
		ORDER BY c.start_date DESC NULLS FIRST
		LIMIT $2 OFFSET $3`;

	const competitions = await db.query(query, [userId, pageSize, (page - 1) * pageSize]);

	// Compute scores for started competitions (same logic as getCompetition singular)
	for (const competition of competitions) {
		if (competition.start_date && new Date(competition.start_date + ' EST') <= new Date()) {
			const userScores = await getUserScores(competition);
			competition.users = competition.users.map((user: CompetitionUser) => ({ ...user, ...userScores[user.user_id] }));
		}
	}

	return competitions;
}

export async function removeUserFromCompetition(competitionId: string, userId: string) {
	await db.query(
		`DELETE FROM competition_users
		WHERE competition_id = $1 AND user_id = $2`,
		[competitionId, userId]
	);
}

export async function sendCompetitionInvite(competitionId: string, inviteUserId: string) {
	await db.query(
		`INSERT INTO competition_users (
			competition_id, user_id, invite_status
		) VALUES (
			$1, $2, 'pending'
		)`,
		[competitionId, inviteUserId]
	);
}

export async function updateCompetitionInvite(
	competitionId: string,
	inviteUserId: string,
	status: 'accepted' | 'declined'
): Promise<CompetitionUser> {
	const [updatedUserStatus] = await db.query(
		`UPDATE competition_users
		SET invite_status = $1
		WHERE competition_id = $2 AND user_id = $3
		RETURNING *`,
		[status, competitionId, inviteUserId]
	);

	return updatedUserStatus;
}

interface UpdateCompetitionParams {
	competitionId: string;
	competition_name?: string;
	start_date?: string;
	end_date?: string;
	workouts?: CompetitionActivity[];
	type?: CompetitionType;
	options?: Partial<CompetitionOptions>;
}

export async function updateCompetition(params: UpdateCompetitionParams): Promise<Competition> {
	const { competitionId, options, ...updateFields } = params;

	const existingCompetition = await getCompetition(competitionId);

	if (!existingCompetition) {
		throw new BadRequestError(`Competition with id ${competitionId} not found`);
	}

	const updates: string[] = [];
	const values: any[] = [];
	let paramIndex = 1;

	for (const [key, value] of Object.entries(updateFields)) {
		if (value !== undefined) {
			if (key === 'workouts') {
				updates.push(`${key} = $${paramIndex}`);
				values.push(JSON.stringify(value));
			} else {
				updates.push(`${key} = $${paramIndex}`);
				values.push(value);
			}
			paramIndex++;
		}
	}

	if (options && Object.keys(options).length > 0) {
		const mergedOptions = {
			...existingCompetition.options,
			...options
		};
		updates.push(`options = $${paramIndex}`);
		values.push(JSON.stringify(mergedOptions));
		paramIndex++;
	}

	if (updates.length === 0) {
		return existingCompetition;
	}

	values.push(competitionId);

	const query = `
		UPDATE competitions
		SET ${updates.join(', ')}
		WHERE id = $${paramIndex}
		RETURNING *
	`;

	const [updatedCompetition] = await db.query(query, values);

	return getCompetition(updatedCompetition.id);
}

export async function deleteCompetition(competitionId: string, userId: string): Promise<void> {
	const competition = await getCompetition(competitionId);

	if (!competition) {
		throw new BadRequestError(`Competition with id ${competitionId} not found`);
	}

	if (competition.owner !== userId) {
		throw new BadRequestError('Only the competition owner can delete it');
	}

	// Delete competition_users first (foreign key), then competition
	await db.query('DELETE FROM competition_users WHERE competition_id = $1', [competitionId]);
	await db.query('DELETE FROM competitions WHERE id = $1', [competitionId]);
}

interface UserData {
	[userId: string]: {
		intervals: {
			[intervalKey: string]: number;
		};
		score: number;
		remaining_lives?: number;
		has_manual_workouts?: boolean;
	};
}

export async function getUserScores(
	competition: Competition,
	{ excludeCurrentInterval = false }: { excludeCurrentInterval?: boolean } = {}
): Promise<UserData> {
	const userData: UserData = {};

	// Only called when start_date is non-null (guarded by caller)
	if (!competition.start_date) return userData;

	// Fix: use for...of loop instead of async reduce (reduce doesn't await)
	// Only process accepted users
	const acceptedUsers = competition.users.filter((u: CompetitionUser) => u.invite_status === 'accepted');

	for (const { user_id } of acceptedUsers) {
		const rawData = await getQuantityDateRange(
			user_id,
			competition.start_date,
			competition.end_date ?? undefined,
			competition.workouts
		);

		const intervals: { [key: string]: number } = rawData.reduce((groupedData: any, dayData: any) => {
			const intervalKey = getCurrentInterval(dayData.local_date, competition.options.interval);
			if (!groupedData[intervalKey]) {
				groupedData[intervalKey] = 0;
			}
			groupedData[intervalKey] += dayData.total_distance;
			return groupedData;
		}, {});

		// Check if user has any manual or edited workouts in the competition period
		const endDate = competition.end_date ?? getTodayET();
		const manualCheck = await db.query(
			`SELECT EXISTS(
				SELECT 1 FROM workouts
				WHERE user_id = $1
				AND local_date >= $2
				AND local_date <= $3
				AND source IN ('manual', 'edited')
			) as has_manual`,
			[user_id, competition.start_date, endDate]
		);

		userData[user_id] = {
			intervals,
			score: 0,
			has_manual_workouts: manualCheck[0]?.has_manual ?? false
		};
	}

	const allIntervals = getIntervalRange(competition);
	const todaysInterval = getCurrentInterval(getTodayET(), competition.options.interval);

	// Determine the inclusive end index for scoring:
	// - If excludeCurrentInterval=true, stop one interval before today.
	// - Otherwise, include today (or end_date if past today).
	const todayIdx = allIntervals.indexOf(todaysInterval);
	let scoringEndIdx: number;
	if (excludeCurrentInterval) {
		scoringEndIdx = todayIdx >= 0 ? todayIdx - 1 : allIntervals.length - 1;
	} else {
		scoringEndIdx = todayIdx >= 0 ? todayIdx : allIntervals.length - 1;
	}

	// Zero-fill userData.intervals for all intervals up to scoringEndIdx
	for (let i = 0; i <= scoringEndIdx; i++) {
		const interval = allIntervals[i];
		Object.keys(userData).forEach(userId => {
			if (!userData[userId].intervals[interval]) {
				userData[userId].intervals[interval] = 0;
			}
		});
	}

	if (competition.type === 'streaks') {
		// Prefer options.lives; fall back to options.first_to for legacy streak competitions.
		const totalLives = competition.options.lives ?? competition.options.first_to ?? 1;

		// Initialize remaining_lives for each user
		Object.keys(userData).forEach(userId => {
			userData[userId].remaining_lives = totalLives;
		});

		for (let i = 0; i <= scoringEndIdx; i++) {
			const interval = allIntervals[i];
			const isToday = interval === todaysInterval;
			Object.keys(userData).forEach(userId => {
				// Once eliminated, stay eliminated — score freezes.
				if ((userData[userId].remaining_lives ?? 0) <= 0) return;

				const userIntervals = userData[userId].intervals;
				if ((userIntervals[interval] ?? 0) >= competition.options.goal) {
					userData[userId].score++;
				} else if (!isToday) {
					// Don't penalize on today's partial-day data.
					userData[userId].remaining_lives!--;
				}
			});
		}
	} else if (competition.type === 'apex') {
		Object.keys(userData).forEach(userId => {
			let score = 0;
			for (let i = 0; i <= scoringEndIdx; i++) {
				score += userData[userId].intervals[allIntervals[i]] ?? 0;
			}
			userData[userId].score = score;
		});
	} else if (competition.type === 'clash') {
		// Clash always excludes today's partial-day data (per-interval head-to-head).
		const clashEndIdx = todayIdx >= 0 ? todayIdx - 1 : scoringEndIdx;
		for (let i = 0; i <= clashEndIdx; i++) {
			const interval = allIntervals[i];
			const userQuantities: { [quantities: number]: string[] } = {};

			Object.keys(userData).forEach(userId => {
				const quantity = userData[userId].intervals[interval] ?? 0;
				if (!Object.keys(userQuantities).includes(quantity.toString())) {
					userQuantities[quantity] = [];
				}
				userQuantities[quantity].push(userId);
			});

			const maxQuantity = Math.max(...Object.keys(userQuantities).map(q => parseFloat(q)));

			if (maxQuantity > 0) {
				userQuantities[maxQuantity].forEach(userId => userData[userId].score++);
			}
		}
	} else if (competition.type === 'targets') {
		for (let i = 0; i <= scoringEndIdx; i++) {
			const interval = allIntervals[i];
			Object.keys(userData).forEach(userId => {
				if ((userData[userId].intervals[interval] ?? 0) >= competition.options.goal) {
					userData[userId].score++;
				}
			});
		}
	} else if (competition.type === 'race') {
		Object.keys(userData).forEach(userId => {
			let score = 0;
			for (let i = 0; i <= scoringEndIdx; i++) {
				score += userData[userId].intervals[allIntervals[i]] ?? 0;
			}
			userData[userId].score = score;
		});
	}

	return userData;
}

function getCurrentInterval(currentDate: Date | string | number, interval?: 'day' | 'week' | 'month'): string {
	let year: number, month: number, day: number;

	if (typeof currentDate === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(currentDate)) {
		[year, month, day] = currentDate.split('-').map(Number);
	} else {
		const date = currentDate instanceof Date ? currentDate : new Date(currentDate);
		const parts = new Intl.DateTimeFormat('en-US', {
			timeZone: 'America/New_York',
			year: 'numeric',
			month: '2-digit',
			day: '2-digit'
		}).formatToParts(date);
		year = parseInt(parts.find(p => p.type === 'year')!.value);
		month = parseInt(parts.find(p => p.type === 'month')!.value);
		day = parseInt(parts.find(p => p.type === 'day')!.value);
	}

	const pad = (n: number) => String(n).padStart(2, '0');

	if (interval === 'week') {
		const d = new Date(year, month - 1, day);
		const daysUntilSunday = (7 - d.getDay()) % 7;
		d.setDate(d.getDate() + daysUntilSunday);
		return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
	} else if (interval === 'month') {
		return `${year}-${pad(month)}`;
	} else {
		return `${year}-${pad(month)}-${pad(day)}`;
	}
}

function getIntervalRange(competition: Competition): string[] {
	if (!competition.start_date) return [];

	const intervals: string[] = [];
	const endDateStr = competition.end_date ?? getTodayET();

	const [sy, sm, sd] = competition.start_date.split('-').map(Number);
	const [ey, em, ed] = endDateStr.split('-').map(Number);

	// Pure calendar-date iteration via UTC math — DST-free because we never mix timezones.
	const endUtcMs = Date.UTC(ey, em - 1, ed);
	let currentMs = Date.UTC(sy, sm - 1, sd);

	if (competition.options.interval === 'week') {
		const dayOfWeek = new Date(currentMs).getUTCDay();
		const daysUntilSunday = (7 - dayOfWeek) % 7;
		currentMs += daysUntilSunday * 86400000;
	}

	const toDateStr = (ms: number): string => {
		const d = new Date(ms);
		const y = d.getUTCFullYear();
		const m = String(d.getUTCMonth() + 1).padStart(2, '0');
		const day = String(d.getUTCDate()).padStart(2, '0');
		return `${y}-${m}-${day}`;
	};

	while (currentMs <= endUtcMs) {
		const intervalKey = getCurrentInterval(toDateStr(currentMs), competition.options.interval);
		intervals.push(intervalKey);

		if (competition.options.interval === 'week') {
			currentMs += 7 * 86400000;
		} else if (competition.options.interval === 'month') {
			const nd = new Date(currentMs);
			nd.setUTCMonth(nd.getUTCMonth() + 1);
			currentMs = nd.getTime();
		} else {
			// 'day' or default
			currentMs += 86400000;
		}
	}

	return intervals;
}

export async function checkRaceCompletions(userId: string): Promise<void> {
	const activeRaces = await db.query<Competition & { id: string }>(
		`SELECT c.*
		FROM competitions c
		JOIN competition_users cu ON cu.competition_id = c.id
		WHERE cu.user_id = $1
			AND cu.invite_status = 'accepted'
			AND c.type = 'race'
			AND c.start_date IS NOT NULL
			AND c.start_date <= (NOW() AT TIME ZONE 'America/New_York')::date
			AND c.winner IS NULL
			AND (c.end_date IS NULL OR c.end_date >= (NOW() AT TIME ZONE 'America/New_York')::date)`,
		[userId]
	);

	if (activeRaces.length === 0) return;

	for (const race of activeRaces) {
		const workoutTypes = (race.workouts ?? ['running', 'walking']).map((t: string) => WORKOUT_TYPE_MAP[t]).filter(Boolean);

		const startDate = race.start_date!;
		const today = getTodayET();
		const endDate = race.end_date ?? today;

		const [result] = await db.query<{ total: number }>(
			`SELECT COALESCE(SUM(distance), 0) as total
			FROM workouts
			WHERE user_id = $1
				AND local_date >= $2
				AND local_date <= $3
				AND workout_type = ANY($4::text[])`,
			[userId, startDate, endDate, workoutTypes]
		);

		if (result.total >= race.options.goal) {
			await db.query(`UPDATE competitions SET end_date = $1, winner = $2, ended = true WHERE id = $3 AND winner IS NULL`, [
				today,
				userId,
				race.id
			]);
			await resolveCompetitionPlacements(race.id);
		}
	}
}

export async function resolveExpiredCompetitions(): Promise<void> {
	const now = new Date();
	const todayStr = getTodayET();

	const candidates = await db.query<Competition & { id: string }>(
		`SELECT c.*, ${USERS_AGG_SQL}
		FROM competitions c
		LEFT JOIN competition_users cu ON cu.competition_id = c.id
		LEFT JOIN users u ON u.user_id = cu.user_id
		WHERE c.start_date IS NOT NULL
			AND c.start_date <= (NOW() AT TIME ZONE 'America/New_York')::date
			AND c.winner IS NULL
		GROUP BY c.id`
	);

	for (const competition of candidates) {
		try {
			await resolveIfComplete(competition, now, todayStr);
		} catch (err: any) {
			console.error(`[CRON] Error resolving competition ${competition.id}:`, err.message);
		}
	}
}

async function resolveIfComplete(competition: Competition, now: Date, todayStr: string): Promise<void> {
	let shouldResolve = false;
	let computedEndDate: string | null = null;

	// Check 1: end_date has passed (string compare is DST-free since both sides are 'YYYY-MM-DD')
	if (competition.end_date && competition.end_date < todayStr) {
		shouldResolve = true;
	}

	// Check 2: duration_hours elapsed (no end_date set yet)
	if (!shouldResolve && !competition.end_date && competition.options.duration_hours && competition.start_date) {
		const startMs = etDateToUtcMs(competition.start_date);
		const durationMs = competition.options.duration_hours * 60 * 60 * 1000;
		if (now.getTime() >= startMs + durationMs) {
			shouldResolve = true;
			computedEndDate = todayStr;
		}
	}

	// Check 3: first_to condition (clash only — races use goal, apex/targets use duration,
	// streaks use first_to as "lives" via checkStreaksEliminated below).
	if (!shouldResolve && competition.options.first_to && competition.type === 'clash') {
		const scores = await getUserScores(competition, { excludeCurrentInterval: true });
		const scoreValues = Object.values(scores);
		if (scoreValues.length > 0) {
			const maxScore = Math.max(...scoreValues.map(s => s.score));
			if (maxScore >= competition.options.first_to) {
				shouldResolve = true;
				computedEndDate = todayStr;
			}
		}
	}

	// Check 3b: streaks — end when one survivor remains (sole survivor wins) or all eliminated
	if (!shouldResolve && competition.type === 'streaks') {
		const scores = await getUserScores(competition, { excludeCurrentInterval: true });
		const scoreValues = Object.values(scores);
		if (scoreValues.length > 0) {
			const survivors = scoreValues.filter(s => (s.remaining_lives ?? 0) > 0);
			const allEliminated = survivors.length === 0;
			const soleSurvivor = scoreValues.length > 1 && survivors.length === 1;
			if (allEliminated || soleSurvivor) {
				shouldResolve = true;
				computedEndDate = todayStr;
			}
		}
	}

	// Check 4: race goal reached (backup for races not caught on upload)
	if (!shouldResolve && competition.type === 'race') {
		const scores = await getUserScores(competition, { excludeCurrentInterval: true });
		for (const data of Object.values(scores)) {
			if (data.score >= competition.options.goal) {
				shouldResolve = true;
				computedEndDate = todayStr;
				break;
			}
		}
	}

	if (!shouldResolve) return;

	if (computedEndDate) {
		await db.query(`UPDATE competitions SET end_date = $1 WHERE id = $2`, [computedEndDate, competition.id]);
		competition.end_date = computedEndDate;
	}

	const finalScores = await getUserScores(competition, { excludeCurrentInterval: true });
	const sortedUsers = Object.entries(finalScores).sort(([, a], [, b]) => b.score - a.score);

	if (sortedUsers.length === 0) return;

	const winnerId = sortedUsers[0][0];
	await db.query(`UPDATE competitions SET winner = $1, ended = true WHERE id = $2 AND winner IS NULL`, [
		winnerId,
		competition.id
	]);

	await resolveCompetitionPlacements(competition.id, finalScores);

	// Notify all accepted participants that the competition finished
	const acceptedUsers = competition.users.filter((u: CompetitionUser) => u.invite_status === 'accepted');
	for (const user of acceptedUsers) {
		sendOrQueueCompetitionNotification(
			user.user_id,
			'competition_finished',
			competition.id,
			competition.competition_name
		).catch(err => console.error('[Push] Error sending competition finish notification:', err.message));
	}
}

async function resolveCompetitionPlacements(competitionId: string, precomputedScores?: UserData): Promise<void> {
	let scores = precomputedScores;
	if (!scores) {
		const competition = await getCompetition(competitionId);
		if (!competition) return;
		scores = await getUserScores(competition);
	}

	const sorted = Object.entries(scores).sort(([, a], [, b]) => b.score - a.score);

	let currentPlacement = 1;
	for (let i = 0; i < sorted.length; i++) {
		const [userId, data] = sorted[i];
		if (i > 0 && data.score < sorted[i - 1][1].score) {
			currentPlacement = i + 1;
		}
		await db.query(`UPDATE competition_users SET placement = $1 WHERE competition_id = $2 AND user_id = $3`, [
			currentPlacement,
			competitionId,
			userId
		]);
	}
}
