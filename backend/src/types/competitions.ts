export type CompetitionActivity = 'running' | 'walking';

export type CompetitionType = 'streaks' | 'apex' | 'clash' | 'targets' | 'race';

export interface CompetitionOptions {
	history?: boolean;
	interval?: 'day' | 'week' | 'month';
	goal: number;
	unit: 'miles' | 'steps';
	first_to: number;
	duration_hours?: number;
	lives?: number;
}

export interface CompetitionUser {
	competition_id: string;
	user_id: string;
	invite_status: string;
	intervals?: { [intervalKey: string]: number };
	score?: number;
	remaining_lives?: number;
	username?: string;
	placement?: number;
}

export interface Competition {
	id: string;
	competition_name: string;
	start_date: string | null;
	end_date: string | null;
	workouts: CompetitionActivity[];
	type: CompetitionType;
	options: CompetitionOptions;
	owner: string;
	winner: string | null;
	users: CompetitionUser[];
}
