export type CompetitionActivity = 'run' | 'walk';

export type CompetitionType = 'streaks' | 'apex' | 'clash' | 'targets' | 'race';

export interface CompetitionOptions {
	history?: boolean;
	interval?: 'day' | 'week' | 'month';
	goal: number;
	unit: 'miles' | 'steps';
	first_to: number;
}

export interface CompetitionUser {
	competition_id: string;
	user_id: string;
	invite_status: string;
}

export interface Competition {
	competition_name: string;
	start_date: string;
	end_date: string;
	workouts: CompetitionActivity[];
	type: CompetitionType;
	options: CompetitionOptions;
	owner: string;
	users: CompetitionUser[];
}
