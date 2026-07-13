/**
 * Canonical "today" boundary used by daily rate limits (hype / nudge / flex).
 *
 * Rate limits reset at midnight in the app's canonical timezone
 * (America/New_York — same one used by the quiet-hours check). A "today"
 * window means `[midnight ET today, midnight ET tomorrow)`.
 *
 * Returns a SQL fragment that evaluates to the start of today (UTC timestamptz)
 * in ET. Use directly in WHERE clauses against a `created_at TIMESTAMPTZ` column.
 */
export const START_OF_TODAY_ET_SQL = `(date_trunc('day', NOW() AT TIME ZONE 'America/New_York') AT TIME ZONE 'America/New_York')`;

/**
 * SQL fragment for the start of tomorrow ET as a UTC timestamptz.
 * Used to report when a rate-limited user can act again.
 */
export const START_OF_TOMORROW_ET_SQL = `((date_trunc('day', NOW() AT TIME ZONE 'America/New_York') + INTERVAL '1 day') AT TIME ZONE 'America/New_York')`;

/**
 * SQL fragment for "today" as a DATE in the app's canonical timezone (ET).
 * Use against DATE columns like workouts.local_date. Plain CURRENT_DATE is the
 * DB server's (UTC) date — from 8pm ET onward it reads as tomorrow, which
 * zeroed the "miles today" counters every evening.
 */
export const TODAY_ET_DATE_SQL = `((NOW() AT TIME ZONE 'America/New_York')::date)`;
