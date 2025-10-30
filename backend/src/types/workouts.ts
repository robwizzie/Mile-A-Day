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
	splitTimes: number[];
};
