import { BadRequestError } from '../errors/Errors.js';
import { Competition, CompetitionActivity, CompetitionOptions, CompetitionType, CompetitionUser } from '../types/competitions.js';
import { PostgresService } from './DbService.js';
import { getQuantityDateRange } from './workoutService.js';

const db = PostgresService.getInstance();

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

		if (end_date === undefined && options.first_to === undefined && options.duration_hours === undefined) {
			missingKeys.push('(first_to, end_date, or duration_hours)');
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
				'username', u.username
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

	// Calculate scores for started competitions (start_date in the past)
	if (competition.start_date && new Date(competition.start_date + ' EST') <= new Date()) {
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

	if (status === 'get_set' || status === 'lobby') {
		statusCondition = 'AND (c.start_date IS NULL OR c.start_date > NOW())';
	} else if (status === 'go') {
		statusCondition = 'AND c.start_date <= NOW() AND (c.end_date IS NULL OR c.end_date > NOW())';
	} else if (status === 'active') {
		// Lobby + currently running (excludes finished)
		statusCondition = 'AND (c.start_date IS NULL OR c.end_date IS NULL OR c.end_date > NOW())';
	} else if (status === 'finished') {
		statusCondition = 'AND (c.end_date IS NOT NULL AND c.end_date < NOW())';
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

	return competitions;
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
	};
}

export async function getUserScores(competition: Competition): Promise<UserData> {
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

		userData[user_id] = { intervals, score: 0 };
	}

	const intervals = getIntervalRange(competition);
	const todaysInterval = getCurrentInterval(new Date(), competition.options.interval);

	for (let interval of intervals) {
		Object.entries(userData).forEach(([userId, { intervals }]) => {
			if (!intervals[interval]) {
				userData[userId].intervals[interval] = 0;
			}
		});

		if (todaysInterval === interval) {
			break;
		}
	}

	if (competition.type === 'streaks') {
		const totalLives = competition.options.lives ?? 1;

		// Initialize remaining_lives for each user
		Object.keys(userData).forEach(userId => {
			userData[userId].remaining_lives = totalLives;
		});

		for (let interval of intervals) {
			Object.entries(userData).forEach(([userId, { intervals }]) => {
				if (intervals[interval] >= competition.options.goal) {
					userData[userId].score++;
				} else if (todaysInterval != interval) {
					userData[userId].remaining_lives!--;
					if (userData[userId].remaining_lives! <= 0) {
						userData[userId].score = 0;
						userData[userId].remaining_lives = totalLives;
					}
				}
			});

			if (todaysInterval === interval) {
				break;
			}
		}
	} else if (competition.type === 'apex') {
		Object.entries(userData).forEach(([userId, { intervals }]) => {
			const score = Object.values(intervals).reduce((total, quantity) => total + quantity, 0);
			userData[userId].score = score;
		});
	} else if (competition.type === 'clash') {
		for (let interval of intervals) {
			if (todaysInterval === interval) {
				break;
			}

			const userQuantities: { [quantities: number]: string[] } = {};

			Object.entries(userData).forEach(([userId, { intervals }]) => {
				const quantity = intervals[interval];

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
		for (let interval of intervals) {
			Object.entries(userData).forEach(([userId, { intervals }]) => {
				if (intervals[interval] >= competition.options.goal) {
					userData[userId].score++;
				}
			});

			if (todaysInterval === interval) {
				break;
			}
		}
	} else if (competition.type === 'race') {
		Object.entries(userData).forEach(([userId, { intervals }]) => {
			const score = Object.values(intervals).reduce((total, quantity) => total + quantity, 0);
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
	const currentDate = new Date(competition.start_date + ' EST');
	const endDate = competition.end_date ? new Date(competition.end_date + ' EST') : new Date();

	const intervals = [];

	if (competition.options.interval === 'week') {
		const dayOfWeek = currentDate.getDay();
		const daysUntilSunday = (7 - dayOfWeek) % 7;
		currentDate.setDate(currentDate.getDate() + daysUntilSunday);
	}

	while (currentDate <= endDate) {
		const intervalKey = getCurrentInterval(currentDate, competition.options.interval);
		intervals.push(intervalKey);

		if (competition.options.interval === 'day') {
			currentDate.setDate(currentDate.getDate() + 1);
		} else if (competition.options.interval === 'week') {
			currentDate.setDate(currentDate.getDate() + 7);
		} else if (competition.options.interval === 'month') {
			currentDate.setMonth(currentDate.getMonth() + 1);
		} else {
			// Default to day if no interval specified
			currentDate.setDate(currentDate.getDate() + 1);
		}
	}

	return intervals;
}
