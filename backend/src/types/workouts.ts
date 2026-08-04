export type WorkoutSource = "healthkit" | "manual" | "edited";

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
  // Seconds of actual movement (in-app tracker only) — display pace uses
  // this; totalDuration stays the elapsed truth for PRs/races/recaps.
  movingSeconds?: number;
  // Ghost race, sent only when the in-app tracker BEAT its ghost over the
  // mile: seconds of margin, and the ghost's own mile time.
  ghostMarginSeconds?: number;
  ghostTargetSeconds?: number;
  splits: WorkoutSplit[];
  source?: WorkoutSource;
  // Optional simplified GPS trace ([[lat, lng], ...]) for outdoor walks/runs.
  route?: [number, number][];
};

export type WorkoutSplit = {
  splitNumber: number;
  distance: number;
  duration: number;
  pace: number;
};
