import { BadRequestError } from '../errors/Errors';
import { PostgresService } from './DbService';

const db = PostgresService.getInstance();

type CompetitionActivity = 'run' | 'walk';

type CompetitionType = 'streaks' | 'apex' | 'clash' | 'targets' | 'race';

interface CompetitionOptions {
	history?: boolean;
	interval?: 'day' | 'week' | 'month';
	goal: number;
	unit: 'miles' | 'steps';
	first_to: number;
}

interface CompetitionUser {
	user_id: string;
}

interface Competition {
	competition_name: string;
	start_date: string;
	end_date: string;
	workouts: CompetitionActivity[];
	type: CompetitionType;
	options: CompetitionOptions;
	owner: string;
	users: CompetitionUser[];
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
            history, workouts, type, options, owner 
        ) VALUES [
            $1, $2, $3, $4, $5, $6, $7, $8
        ] RETURNING *;`,
		[competition_name, start_date, end_date, history, workouts, type, options, owner]
	);

	await db.query(
		`INSERT INTO competition_users (
            competition_id, user_id, progress, invite_status
        ) VALUES [
            $1, $2, 0, 'joined'
        ]`,
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

	if (owner) {
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
		requiredKeys.push('goal', 'unit', 'inoerval');

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
			) FILTER (WHERE cu.id IS NOT NULL),
			'[]'
		) as competition_users
		FROM competitions c
		LEFT JOIN competition_users cu ON cu.competition_id = c.id
		WHERE c.id = $1
		GROUP BY c.id;`,
			[competitionId]
		)
	)[0];

	return competition;
}

export async function getCompetitions(userId: string, status?: string) {}

export async function updateCompetition(competitionId, updates) {}
