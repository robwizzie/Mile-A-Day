/**
 * What counts as a real mile time.
 *
 * `workout_splits.split_pace` is seconds per mile, computed from whatever
 * HealthKit hands us. Nothing upstream distinguishes a mile RUN from a mile
 * COVERED — a walk left tracking in a car produces a perfectly well-formed
 * split at 90 seconds, and until now every query that showed a "fastest mile"
 * bounded it only by `split_pace > 0`. So that 90-second drive became the
 * user's PR, topped the pace leaderboard, and unlocked pace badges.
 *
 * The floor is 4:01 because the mile world record is 3:43. Anything at or
 * under 4:01 from a consumer phone is a vehicle, a GPS glitch, or a
 * mis-segmented split — never a person. Deliberately generous in the sense
 * that it lets through times no real user of this app will hit either; the
 * point is to be unarguable rather than tight.
 *
 * This bounds what is DISPLAYED as a mile time. It deliberately does NOT
 * exclude the workout's distance from miles or streaks — that's
 * `exclusion_reason`'s job, decided per WORKOUT by average speed. A single
 * bogus split inside an otherwise-real walk shouldn't cost someone their day.
 */
export const MIN_PLAUSIBLE_MILE_SECONDS = 241; // 4:01

/** 40:00. A mile slower than this is a stroll that stopped being a mile. */
export const MAX_PLAUSIBLE_MILE_SECONDS = 2400;

/**
 * SQL predicate for "this split is a believable mile time".
 *
 * `paceCol` is a column expression from the caller's own query (e.g.
 * `ws.split_pace`) — a compile-time value, never request input.
 *
 * Pair it with the caller's own distance floor: the leaderboard and the ghost
 * picker use `>= 0.999` (which excludes SplitCalculator's extrapolated
 * trailing partial), while badges and PR detection use the legacy `>= 0.95`.
 */
export function realMileSplitSql(paceCol: string): string {
  return `${paceCol} >= ${MIN_PLAUSIBLE_MILE_SECONDS}`;
}

/**
 * SQL predicate for "this workout COUNTS" — not deleted, and not excluded by
 * the duplicate/vehicle/consent passes (`exclusion_reason`).
 *
 * Every query that SUMs `distance` already spells this out inline, but the
 * ones that reach workouts through `workout_splits` did not: a Strava copy of
 * a run that HealthKit already recorded, or a drive classified `vehicle_speed`,
 * still owned the fastest split. So the same ride that was kept out of the
 * user's miles could win Speed Round, and — because `beat_your_pace` compares
 * against the all-time best split BEFORE the day — could raise the bar
 * permanently and make that challenge unwinnable.
 *
 * `alias` is a table alias from the caller's own query, never request input.
 */
export function countedWorkoutSql(alias: string): string {
  return `${alias}.deleted_at IS NULL AND ${alias}.exclusion_reason IS NULL`;
}

/** The same check for values already in JS. */
export function isPlausibleMileSeconds(seconds: unknown): boolean {
  const value = Number(seconds);
  return (
    Number.isFinite(value) &&
    value >= MIN_PLAUSIBLE_MILE_SECONDS &&
    value <= MAX_PLAUSIBLE_MILE_SECONDS
  );
}

/**
 * "9:12" from seconds per mile — the one mile-pace formatter.
 *
 * Both challenge families print a pace the user has to beat (`beat_your_pace`
 * daily, `personal_best` weekly) and they had started from two separate copies
 * of this rounding. A pace that reads 9:12 on one screen and 9:13 on the other
 * is the kind of difference nobody reports and everybody notices.
 */
export function formatMilePace(secondsPerMile: number): string {
  const total = Math.round(secondsPerMile);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s < 10 ? `0${s}` : s}`;
}
