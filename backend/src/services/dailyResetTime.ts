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
 * A user's CURRENT UTC offset in minutes, as a nullable SQL expression.
 *
 * Precedence: the offset the app reports on every launch
 * (`notification_settings.timezone_offset_minutes`, synced by
 * `MADNotificationService.syncDailyReminderPrefsToBackend`), then the offset
 * stamped on their most recent workout, then NULL. A workout's offset is
 * frozen at the time of that workout, so after a DST change it is an hour off
 * until the user logs another one; the app-reported one is not.
 *
 * This is THE rule for "the user's local now / today". Every streak, stats,
 * cron and display surface reads it — the streak writer (`refreshStoredStreak`
 * via `userTodaySql`) and every reader must agree, or "today" means two
 * things. Never inline `SELECT timezone_offset FROM workouts … ORDER BY
 * device_end_date DESC LIMIT 1` again. (A workout's OWN `local_date` /
 * `timezone_offset` is still that workout's day — this is only for "now".)
 *
 * `userIdCol` is interpolated directly, so it must be a code-controlled column
 * reference or placeholder (e.g. "u.user_id", "$1", "$1::text") and NEVER
 * user input. The inner aliases (`uo_ns`, `uo_w`) are unique so a caller's
 * `w.user_id` is never shadowed. Both lookups are single-row index probes (notification_settings
 * PK, idx_workouts_user_device_end), so this is fine per row in a list query.
 */
export function userOffsetMinutesOrNullSql(userIdCol: string): string {
  return `COALESCE(
		(SELECT uo_ns.timezone_offset_minutes FROM notification_settings uo_ns WHERE uo_ns.user_id = ${userIdCol}),
		(SELECT uo_w.timezone_offset FROM workouts uo_w WHERE uo_w.user_id = ${userIdCol} ORDER BY uo_w.device_end_date DESC LIMIT 1))`;
}

/** `userOffsetMinutesOrNullSql`, falling back to UTC (0) when neither is known. */
export function userOffsetMinutesSql(userIdCol: string): string {
  return `COALESCE(${userOffsetMinutesOrNullSql(userIdCol)}, 0)`;
}

/** The `$1`-is-the-user variant, for single-user queries. */
export const USER_OFFSET_MINUTES_P1_SQL = userOffsetMinutesSql("$1");

/**
 * A given user's local "now" as a tz-less timestamp.
 *
 * Unlike the ET constants above — which define one canonical daily boundary for
 * everyone — this resolves each user's OWN wall clock, so hourly crons can
 * defer a push into that user's daytime. Offset from `userOffsetMinutesSql`.
 *
 * `col` is interpolated directly, so it must be a code-controlled column
 * reference (e.g. "m.user_id") and NEVER user input.
 *
 * Every hourly "send during the user's daytime" job shares this: the h2h winner
 * push, the daily reminder, the weekly recap, and the friend-request reminder.
 * It lives here rather than in any one of them so the four cannot drift apart.
 */
export function localNowSql(col: string): string {
  return `((NOW() AT TIME ZONE 'UTC') + (${userOffsetMinutesSql(col)} || ' minutes')::interval)`;
}
