import { BadRequestError } from '../errors/Errors';
import { Competition, CompetitionActivity, CompetitionOptions, CompetitionType, CompetitionUser } from '../types/competitions';
import { PostgresService } from './DbService';

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
		[competition_name, start_date, end_date, JSON.stringify(workouts), type, JSON.stringify(options), owner]
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

		if (end_date === undefined) {
			missingKeys.push('end_date');
		}
	} else if (type === 'clash' || type === 'targets') {
		requiredKeys.push('goal', 'unit', 'interval');

		if (end_date === undefined && options.first_to === undefined) {
			missingKeys.push('(first_to or end_date)');
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

export async function getCompetition(competitionId: string): Promise<Competition> {
	const competition = (
		await db.query(
			`SELECT 
		c.*,
		COALESCE(
			jsonb_agg(
				cu.*
			) FILTER (WHERE c.id IS NOT NULL),
			'[]'
		) as users
		FROM competitions c
		LEFT JOIN competition_users cu ON cu.competition_id = c.id
		WHERE c.id = $1
		GROUP BY c.id;`,
			[competitionId]
		)
	)[0];

	return competition;
}

export async function getCompetitions(
	userId: string,
	{ page = 1, status = 'go', pageSize = 10 }: { page: number; status: string; pageSize: number }
): Promise<Competition[]> {
	let statusCondition = '';

	if (status === 'get_set') {
		statusCondition = 'AND (start_date IS NULL OR start_date > NOW())';
	} else if (status === 'go') {
		statusCondition = 'AND start_date < NOW() AND (end_date IS NULL OR end_date > NOW())';
	} else if (status === 'finished') {
		statusCondition = 'AND (end_date < NOW())';
	}

	const query = `SELECT 
			c.*,
  			COALESCE(
				jsonb_agg(cu.*) FILTER (WHERE c.id IS NOT NULL),
				'[]'
			) as users
		FROM competitions c
		LEFT JOIN competition_users cu ON cu.competition_id = c.id
		WHERE c.id IN (
			SELECT competition_id 
	  		FROM competition_users 
	  		WHERE user_id = $1
			${status === 'on_your_mark' ? "AND invite_status = 'pending'" : "AND invite_status = 'accepted'"}
		)
		GROUP BY c.id
		${statusCondition}
		LIMIT $2 OFFSET $3`;

	const competitions = await db.query(query, [userId, pageSize, page - 1]);

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

// TODO: you can only invite friends to competitions

// TODO: order get competitions by start/end dates
