export interface UserStats {
	user_id: string;
	streak: number;
	total_miles: number;
	fastest_mile_pace: number;
	most_miles_in_one_day: number;
	last_completion_date: Date | null;
	goal_miles: number;
}

export interface Badge {
	badge_id?: number;
	user_id: string;
	badge_key: string;
	name: string;
	description: string;
	date_awarded: Date;
	is_new: boolean;
}

export interface UpdateStatsRequest {
	streak: number;
	total_miles: number;
	fastest_mile_pace: number;
	most_miles_in_one_day: number;
	last_completion_date?: string | null;
	goal_miles?: number;
}

export interface UserStatsResponse {
	stats: UserStats;
	badges: Badge[];
}
