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
  // Whose ghost it was, when the raced target was a friend's mile. Client-
  // asserted; the friendship is re-checked before any push goes out.
  ghostFriendUserId?: string;
  // HealthKit's indoor-workout metadata. Optional: older clients omit it,
  // and absence must never overwrite a value already recorded (COALESCE in
  // the upsert).
  isIndoor?: boolean;
  // Client-asserted "recorded while Stealth Mode was on". The server ORs it
  // with its own stealth_windows overlap and the stamp is STICKY, so this can
  // only ever ADD hiding, never remove it. Optional: older clients omit it.
  stealth?: boolean;
  splits: WorkoutSplit[];
  source?: WorkoutSource;
  // Bundle id of the app that wrote this workout into HealthKit
  // (com.strava.stravaride, com.garmin.connect.mobile, …). Optional: older
  // clients don't send it, and those workouts just never take part in
  // cross-app duplicate detection.
  sourceBundleId?: string;
  // Optional simplified GPS trace for outdoor walks/runs. Each point is
  // [lat, lng] or — newer clients — [lat, lng, altitudeMeters]: elevation
  // groundwork, stored so climb features have history the day they exist.
  // Every consumer reads [0]/[1] and tolerates the extra element.
  route?: RoutePoint[];
};

export type RoutePoint = [number, number] | [number, number, number];

export type WorkoutSplit = {
  splitNumber: number;
  distance: number;
  duration: number;
  pace: number;
};
