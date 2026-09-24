import { PostgresService } from "./DbService.js";
import { areFriends } from "./friendshipService.js";
import { effectiveStreakSql } from "./streakFeatureCore.js";
import { HOLIDAYS, holidayKeyFromBadgeId, type HolidayKey } from "./holidays.js";

const db = PostgresService.getInstance();

/**
 * Flamey (the flame mascot) lives on the app's "Fun" dashboard only. The
 * server learns which dashboard a device draws from `users.dashboard_style`
 * (PATCH /users/:id); NULL is a build that predates the field and is treated
 * exactly like 'modern' by every Flamey gate.
 */
export const DASHBOARD_STYLES = new Set(["fun", "modern"]);

export function isFunStyle(style: unknown): boolean {
  return style === "fun";
}

export type FlameyBlock =
  | { enabled: false }
  | {
      enabled: true;
      longest_streak: number;
      holiday_keys: HolidayKey[];
      signup_date: string;
    };

/**
 * The additive `flamey` block on `GET /users/:id`.
 *
 * Enabled only when the TARGET draws the Fun dashboard AND the viewer may see
 * what it carries: `holiday_keys` are medals, and medals are friends-only
 * (`GET /users/:id/badges` 403s a stranger) — so a stranger gets
 * `{enabled:false}`, never a block with the medals scrubbed out (which would
 * read as "has none"). Self always sees their own.
 *
 * Everything is read from stored columns + the user's badge rows — no
 * history walk per read: `longest_streak` is the ratcheted column, raised to
 * the live effective streak (the column reads 0 until its own backfill lands).
 */
export async function flameyBlockFor(
  viewerId: string | undefined,
  targetUserId: string,
): Promise<FlameyBlock> {
  const rows = await db.query<{
    dashboard_style: string | null;
    longest_streak: number;
    signup_date: string;
  }>(
    `SELECT u.dashboard_style,
	        GREATEST(u.longest_streak, (${effectiveStreakSql("u")}))::int AS longest_streak,
	        to_char(((u.created_at AT TIME ZONE 'UTC') + (COALESCE(
	            (SELECT ns.timezone_offset_minutes FROM notification_settings ns WHERE ns.user_id = u.user_id),
	            (SELECT w.timezone_offset FROM workouts w WHERE w.user_id = u.user_id ORDER BY w.device_end_date DESC LIMIT 1),
	            0) || ' minutes')::interval)::date, 'YYYY-MM-DD') AS signup_date
	   FROM users u WHERE u.user_id = $1`,
    [targetUserId],
  );
  const row = rows[0];
  if (!row || !isFunStyle(row.dashboard_style)) return { enabled: false };
  if (!viewerId || !(await areFriends(viewerId, targetUserId))) {
    return { enabled: false };
  }

  const badgeRows = await db.query<{ badge_id: string }>(
    `SELECT badge_id FROM user_badges WHERE user_id = $1 AND badge_id LIKE 'holiday\\_%'`,
    [targetUserId],
  );
  const held = new Set(
    badgeRows
      .map((r) => holidayKeyFromBadgeId(r.badge_id))
      .filter((k): k is HolidayKey => k !== null),
  );
  return {
    enabled: true,
    longest_streak: Number(row.longest_streak) || 0,
    // Catalog (calendar) order, so the client can lay them out as-is.
    holiday_keys: HOLIDAYS.map((h) => h.key).filter((k) => held.has(k)),
    signup_date: row.signup_date,
  };
}

/** Both sides draw Flamey — the gate for a Flamey poke. */
export async function bothUseFun(a: string, b: string): Promise<boolean> {
  const rows = await db.query<{ n: number }>(
    `SELECT COUNT(*)::int AS n FROM users
	  WHERE user_id = ANY($1::text[]) AND dashboard_style = 'fun'`,
    [[a, b]],
  );
  return (rows[0]?.n ?? 0) === 2;
}
