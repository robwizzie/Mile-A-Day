export type Workout = {
	workoutId: string;
	distance: number;
	localDate: string;
	date: string;
	timezoneOffset: number;
	workoutType: string;
	deviceEndDate: string;
	calories: number;
	totalDuration: number;
	splits: WorkoutSplit[];
};

export type WorkoutSplit = {
	splitNumber: number;
	distance: number;
	duration: number;
	pace: number;
};
