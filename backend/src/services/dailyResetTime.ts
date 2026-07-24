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

/**
 * A given user's local "now" as a tz-less timestamp.
 *
 * Unlike the ET constants above — which define one canonical daily boundary for
 * everyone — this resolves each user's OWN wall clock, so hourly crons can
 * defer a push into that user's daytime. Offset precedence: the app-reported
 * notification offset, then the most recent workout's offset, then UTC.
 *
 * `col` is interpolated directly, so it must be a code-controlled column
 * reference (e.g. "m.user_id") and NEVER user input.
 *
 * Every hourly "send during the user's daytime" job shares this: the h2h winner
 * push, the daily reminder, the weekly recap, and the friend-request reminder.
 * It lives here rather than in any one of them so the four cannot drift apart.
 */
export function localNowSql(col: string): string {
  return `((NOW() AT TIME ZONE 'UTC') + (COALESCE(
		(SELECT ns.timezone_offset_minutes FROM notification_settings ns WHERE ns.user_id = ${col}),
		(SELECT w.timezone_offset FROM workouts w WHERE w.user_id = ${col} ORDER BY w.device_end_date DESC LIMIT 1),
		0) || ' minutes')::interval)`;
}
