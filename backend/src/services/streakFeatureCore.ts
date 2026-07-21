import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

/**
 * Low-level streak-features plumbing shared by the streak walks. Deliberately
 * imports ONLY DbService so both workoutService and leaderboardService can use
 * it without an import cycle (the high-level token logic lives in
 * streakFeatureService, which imports those services in turn).
 *
 * The safety contract of the whole feature lives here:
 *   - the per-user gate is the ENROLLMENT STAMP, which only app builds that
 *     ship the token UI write — so the feature reaches a user exactly when
 *     their app can display it. Un-enrolled users' streak math runs the EXACT
 *     legacy code path — the callers branch before any of this runs.
 *   - STREAK_FEATURES_DISABLED=true is the emergency kill switch: it freezes
 *     every token behavior (walks fall back to legacy, no earning/consuming,
 *     no pushes) for everyone without needing an app release. Normally unset.
 *   - a covered day (one streak_coverage row) counts as "not a miss" in the
 *     walk, no matter WHICH token wrote it. The walks never branch per token.
 */

export function streakFeaturesGloballyEnabled(): boolean {
  // ON by default everywhere — enrollment does the targeting. The env var is
  // only the emergency brake, deliberately inverted (fail-open) now that the
  // feature is code-complete: nothing to remember at launch, one line of
  // config to freeze it in an incident.
  return process.env.STREAK_FEATURES_DISABLED !== "true";
}

/** One users-row read of everything the token logic needs. */
export interface StreakFeatureUserRow {
  streak_features_at: string | null;
  double_down_last_used: string | null;
  streak_save_last_used: string | null;
  streak_assist_last_used: string | null;
  goal_miles: string | number;
  current_streak: number;
}

export async function getStreakFeatureRow(
  userId: string,
): Promise<StreakFeatureUserRow | null> {
  const rows = await db.query<StreakFeatureUserRow>(
    `SELECT streak_features_at, double_down_last_used, streak_save_last_used,
            streak_assist_last_used, goal_miles, current_streak
     FROM users WHERE user_id = $1`,
    [userId],
  );
  return rows[0] ?? null;
}

/**
 * Should this user's streak walk honor coverage? False for everyone until the
 * env switch flips AND the user's (new-build-only) enrollment stamp exists —
 * the callers run their untouched legacy code in that case, so live users'
 * streak output stays byte-identical.
 */
export async function coverageActiveFor(userId: string): Promise<boolean> {
  if (!streakFeaturesGloballyEnabled()) return false;
  const rows = await db.query<{ enrolled: boolean }>(
    `SELECT (streak_features_at IS NOT NULL) AS enrolled FROM users WHERE user_id = $1`,
    [userId],
  );
  return rows[0]?.enrolled === true;
}

/** All covered local dates for a user, newest first (tiny — days are rare). */
export async function fetchCoverageDates(userId: string): Promise<string[]> {
  const rows = await db.query<{ d: string }>(
    `SELECT to_char(local_date, 'YYYY-MM-DD') AS d
     FROM streak_coverage WHERE user_id = $1
     ORDER BY local_date DESC`,
    [userId],
  );
  return rows.map((r) => r.d);
}

/** Shared YYYY-MM-DD date arithmetic (UTC-safe, mirrors the legacy walks'). */
export function dateStrMinus(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

/**
 * The coverage-aware streak walk: identical anchor/grace/consecutive semantics
 * to the legacy walks (today counts if present but isn't required; stop at the
 * first uncovered miss), over the UNION of qualifying workout days and covered
 * days. Paginates the same qualifying-days query the legacy walk uses.
 *
 * Only ever called for enrolled users with the env switch on.
 */
export async function computeCoveredStreak(
  userId: string,
  userToday: string,
): Promise<{ streak: number; start: string | undefined }> {
  const coverage = await fetchCoverageDates(userId); // DESC
  const yesterday = dateStrMinus(userToday, 1);

  const qualifyingDaysQuery = `
    SELECT to_char(local_date, 'YYYY-MM-DD') AS local_date
    FROM workouts
    WHERE user_id = $1
    AND deleted_at IS NULL AND exclusion_reason IS NULL
    GROUP BY local_date
    HAVING SUM(distance) >= 0.95
    ORDER BY local_date DESC
    LIMIT $2 OFFSET $3
  `;
  const LIMIT = 100;

  // Lazily merge the paginated qualifying stream with the (small) coverage
  // list, descending, de-duped — a backfilled workout can land on an
  // already-covered day and must not count twice.
  let pageIndex = 0;
  let page: { local_date: string }[] = await db.query(qualifyingDaysQuery, [
    userId,
    LIMIT,
    0,
  ]);
  let pi = 0; // cursor into page
  let ci = 0; // cursor into coverage
  let last: string | undefined;

  const next = async (): Promise<string | undefined> => {
    while (true) {
      if (pi >= page.length && page.length === LIMIT) {
        pageIndex++;
        page = await db.query(qualifyingDaysQuery, [
          userId,
          LIMIT,
          pageIndex * LIMIT,
        ]);
        pi = 0;
      }
      const q = pi < page.length ? page[pi].local_date : undefined;
      const c = ci < coverage.length ? coverage[ci] : undefined;
      let candidate: string | undefined;
      if (q !== undefined && (c === undefined || q >= c)) {
        candidate = q;
        pi++;
        if (c !== undefined && c === q) ci++; // dupe: consume both
      } else if (c !== undefined) {
        candidate = c;
        ci++;
      } else {
        return undefined;
      }
      if (candidate === last) continue; // safety de-dupe
      last = candidate;
      return candidate;
    }
  };

  let streak = 0;
  let streakStartDay: string | undefined;
  let expectedDate: string | undefined;

  while (true) {
    const date = await next();
    if (date === undefined) break;

    if (expectedDate === undefined) {
      if (date !== userToday && date !== yesterday) {
        return { streak: 0, start: undefined };
      }
      streak = 1;
      streakStartDay = date;
      expectedDate = dateStrMinus(date, 1);
    } else if (date === expectedDate) {
      streak++;
      streakStartDay = date;
      expectedDate = dateStrMinus(date, 1);
    } else {
      return { streak, start: streakStartDay };
    }
  }

  return { streak, start: streakStartDay };
}

/**
 * Length of the consecutive qualified-or-covered run ENDING exactly at
 * `endDate` (0 when endDate itself doesn't qualify). Used for the
 * prior-streak stamped on a break event — i.e. what an assist would restore.
 */
export async function streakEndingAt(
  userId: string,
  endDate: string,
): Promise<number> {
  const rows = await db.query<{ len: number; max_d: string }>(
    `WITH days AS (
       SELECT local_date FROM workouts
       WHERE user_id = $1 AND local_date <= $2::date
         AND deleted_at IS NULL AND exclusion_reason IS NULL
       GROUP BY local_date HAVING SUM(distance) >= 0.95
       UNION
       SELECT local_date FROM streak_coverage
       WHERE user_id = $1 AND local_date <= $2::date
     ),
     numbered AS (
       SELECT local_date,
              local_date - (ROW_NUMBER() OVER (ORDER BY local_date DESC))::int AS grp
       FROM days
     )
     SELECT COUNT(*)::int AS len,
            to_char(MAX(local_date), 'YYYY-MM-DD') AS max_d
     FROM numbered
     WHERE grp = (SELECT grp FROM numbered LIMIT 1)`,
    [userId, endDate],
  );
  const row = rows[0];
  if (!row || !row.max_d) return 0;
  return row.max_d === endDate ? Number(row.len) : 0;
}
