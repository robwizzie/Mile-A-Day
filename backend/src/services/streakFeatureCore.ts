import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

/**
 * The streak: how it is computed, how it is STORED, and how it is read.
 *
 * Deliberately imports ONLY DbService so workoutService, leaderboardService
 * and friendshipService can all use it without an import cycle (the
 * high-level token logic lives in streakFeatureService, which imports those
 * services in turn).
 *
 * THE RULE: nothing recomputes a streak on a read path. `users.current_streak`
 * is a stored snapshot, written only by `refreshStoredStreak`, and every read
 * (`readStoredStreak`, `effectiveStreakSql`) applies the calendar decay itself
 * from `streak_valid_through`. So every mutation that can change which days
 * qualify — a workout upload/edit/delete/exclusion, a coverage row, a pause —
 * MUST call refreshStoredStreak (via leaderboardService.refreshCurrentStreak).
 * Miss one and the number is stale until the daily reconcile.
 *
 * Why it's built this way: the previous walks paginated qualifying days 100 at
 * a time (each page re-aggregating the user's whole history — O(N²) for a
 * 2,000-day streak), the stored writer was capped at `LIMIT 500` (so every
 * streak over 500 days read back as exactly 500, including from Recalibrate),
 * and the friends list re-ran the whole thing for EVERY friend on EVERY read.
 * Now a recompute is ONE gaps-and-islands query and a read is one row.
 *
 * The safety contract of the token feature still lives here:
 *   - the per-user gate is the ENROLLMENT STAMP, which only app builds that
 *     ship the token UI write — so the feature reaches a user exactly when
 *     their app can display it. Un-enrolled users never see coverage.
 *   - STREAK_FEATURES_DISABLED=true is the emergency kill switch: it freezes
 *     every token behavior (coverage ignored, no earning/consuming, no pushes)
 *     for everyone without needing an app release. Normally unset. Pauses are
 *     NOT behind it — see needsFeatureWalk for why.
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

/**
 * A day qualifies for the streak when its counted miles reach this. It is
 * workoutService.DAILY_GOAL_TOLERANCE (0.95 — a GPS 0.98-mile day must not
 * break a streak), restated here because this module can't import that file.
 */
export const STREAK_QUALIFYING_MILES = 0.95;

/** One users-row read of everything the token logic needs. */
export interface StreakFeatureUserRow {
  // timestamptz: node-pg parses this to a JS Date (unlike `date` columns,
  // which arrive as strings) — never call string methods on it directly.
  streak_features_at: string | Date | null;
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
 * Should this user's streak honor coverage? False for everyone until the
 * env switch is on AND the user's (new-build-only) enrollment stamp exists.
 */
export async function coverageActiveFor(userId: string): Promise<boolean> {
  if (!streakFeaturesGloballyEnabled()) return false;
  const rows = await db.query<{ enrolled: boolean }>(
    `SELECT (streak_features_at IS NOT NULL) AS enrolled FROM users WHERE user_id = $1`,
    [userId],
  );
  return rows[0]?.enrolled === true;
}

/**
 * Does this user's streak need coverage or pause handling? Kept for callers
 * that branch on it; the walks themselves no longer need to be told — they
 * read the user's enrollment and pauses in the same query as everything else.
 *
 * The pause half is a safety interlock, not an optimization: killing the
 * tokens (STREAK_FEATURES_DISABLED) must never un-bridge a pause, because
 * refreshStoredStreak would then persist a frozen streak as BROKEN, and that
 * write is not recoverable.
 */
export async function needsFeatureWalk(userId: string): Promise<boolean> {
  if (await coverageActiveFor(userId)) return true;
  return (await fetchPauseIntervals(userId)).length > 0;
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

/**
 * One day a token carried, with enough detail for a client to SAY so.
 *
 * Every per-day surface in the app paints from raw mileage, so a token-covered
 * day renders identically to a plain miss — 0.57 mi in orange — while the
 * streak walks quietly count it. That mismatch is not cosmetic: it makes a
 * correct Save Streak offer look like it is inventing a day the user can see
 * they missed. Anything that draws a day needs this list.
 */
export interface CoveredDay {
  local_date: string;
  /** 'streak_save' | 'double_down_recover' | 'streak_assist' */
  kind: string;
  /** Assist only: who rescued them, for "Saved by alex". */
  source_username: string | null;
}

/**
 * Covered days for a user, newest first, optionally from `sinceDate` on.
 *
 * Returns [] whenever coverage is not ACTIVE for this user (env off, or not
 * enrolled) — those users' streaks ignore coverage entirely, so reporting
 * covered days would explain a save that never happened.
 */
export async function fetchCoveredDays(
  userId: string,
  sinceDate?: string,
): Promise<CoveredDay[]> {
  if (!(await coverageActiveFor(userId))) return [];
  const params: string[] = [userId];
  let where = `sc.user_id = $1`;
  if (sinceDate) {
    params.push(sinceDate);
    where += ` AND sc.local_date >= $2::date`;
  }
  return db.query<CoveredDay>(
    `SELECT to_char(sc.local_date, 'YYYY-MM-DD') AS local_date,
            sc.kind,
            su.username AS source_username
       FROM streak_coverage sc
       LEFT JOIN users su ON su.user_id = sc.source_user
      WHERE ${where}
      ORDER BY sc.local_date DESC`,
    params,
  );
}

/**
 * One injury pause, as a HALF-OPEN local-date interval: paused = [started_on,
 * resumed_on), so the day a user resumes is immediately a running day again.
 * An ACTIVE pause has resumed_on === null and extends to today.
 */
export interface PauseInterval {
  started_on: string;
  resumed_on: string | null;
  /** Ran past the 180-day cap: still suppresses its days, no longer bridges. */
  expired: boolean;
}

/** Every pause on record, newest first — expired ones included, see below. */
export async function fetchPauseIntervals(
  userId: string,
): Promise<PauseInterval[]> {
  const rows = await db.query<PauseInterval>(
    `SELECT to_char(started_on, 'YYYY-MM-DD') AS started_on,
            to_char(resumed_on, 'YYYY-MM-DD') AS resumed_on,
            (expired_at IS NOT NULL) AS expired
       FROM streak_pauses
      WHERE user_id = $1
      ORDER BY started_on DESC`,
    [userId],
  );
  return rows;
}

/**
 * "Is this local date inside a pause?" over a (tiny) interval list.
 *
 * A pause ELIDES days rather than covering them, and that distinction is the
 * whole feature. A streak_coverage row COUNTS as a day in the walk, so
 * covering a 90-day injury would hand the user 90 free streak days — the exact
 * opposite of the rule that a paused streak must not grow. Eliding instead
 * removes the days from the calendar: the run either side joins up and the
 * number is frozen, not inflated.
 */
export function makePausePredicate(
  intervals: PauseInterval[],
): (d: string) => boolean {
  if (intervals.length === 0) return () => false;
  return (d: string) =>
    intervals.some(
      (p) => d >= p.started_on && (p.resumed_on === null || d < p.resumed_on),
    );
}

/**
 * The two halves of a pause, which come apart once it expires.
 *
 * SUPPRESS asks "did this day earn nothing?" and covers EVERY pause. BRIDGE
 * asks "do the days either side join up?" and covers only live ones.
 *
 * They're identical for an active pause and deliberately not for an expired
 * one. People do walk during recovery — PT laps, an easy mile — and rule one of
 * a pause is that those days earn nothing. If expiry simply dropped the
 * interval, every one of those walks would spring back into the walk as an
 * ordinary qualifying day and could carry the streak straight through the cap,
 * which is precisely the zombie streak the 180-day ceiling exists to end.
 * Suppressing without bridging leaves what the cap is supposed to leave: a
 * hard gap, and longest_streak holding the frozen number.
 */
export function makePauseGates(intervals: PauseInterval[]): {
  suppress: (d: string) => boolean;
  bridge: (d: string) => boolean;
} {
  return {
    suppress: makePausePredicate(intervals),
    bridge: makePausePredicate(intervals.filter((p) => !p.expired)),
  };
}

/**
 * Walk `d` backwards past any paused days to the first day that actually
 * counts. This is what makes the two ends of a pause adjacent: with a pause
 * over [Jan 1, Mar 1), the day "before" Mar 1 is Dec 31.
 *
 * Bounded by a hard step budget so a corrupt interval (e.g. a pause with a
 * started_on far in the past that never resumed) can never spin forever inside
 * a streak read.
 */
export function elidePaused(
  d: string,
  isPaused: (day: string) => boolean,
): string {
  let cur = d;
  for (let i = 0; i < MAX_PAUSE_ELIDE_DAYS && isPaused(cur); i++) {
    cur = dateStrMinus(cur, 1);
  }
  return cur;
}

/** Generous ceiling: the product cap is 180 days, so this is only a backstop. */
const MAX_PAUSE_ELIDE_DAYS = 400;

/** Shared YYYY-MM-DD date arithmetic (UTC-safe, mirrors the legacy walks'). */
export function dateStrMinus(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

/** The other direction, for walking a window forward. */
export function dateStrPlus(dateStr: string, days: number): string {
  return dateStrMinus(dateStr, -days);
}

// ─── The user's "today" ────────────────────────────────────────────────────

/**
 * Today's date in the user's local timezone, as a SQL expression over a
 * `users` row aliased `alias`: derived from the timezone_offset of their most
 * recent workout (UTC if they have none) — the same derivation every streak
 * and stats surface uses, so "today" can never mean two things.
 * Index-backed per row (idx_workouts_user_device_end), so it's fine inside a
 * list query.
 */
export function userTodaySql(alias: string): string {
  return `(NOW() + (COALESCE((
      SELECT w.timezone_offset FROM workouts w
      WHERE w.user_id = ${alias}.user_id
      ORDER BY w.device_end_date DESC LIMIT 1), 0) || ' minutes')::interval)::date`;
}

/**
 * The stored streak WITH the calendar decay applied, as a SQL expression over
 * a `users` row aliased `alias` — for lists (friends, nudge status) that used
 * to recompute every member's streak on every read. A row past its
 * `streak_valid_through` reads 0; a null valid-through (frozen by a pause, or
 * a legacy row the boot sweep hasn't reached) reads the column as-is.
 */
export function effectiveStreakSql(alias: string): string {
  return `CASE WHEN ${alias}.streak_valid_through IS NOT NULL
               AND ${alias}.streak_valid_through < ${userTodaySql(alias)}
          THEN 0 ELSE ${alias}.current_streak END`;
}

// ─── Qualifying days ───────────────────────────────────────────────────────

/**
 * The user's qualifying days ($1 = user, $2 = the latest day to consider):
 * every local_date whose counted miles reach the threshold, UNIONed with their
 * covered days when coverage applies. Un-enrolled users get the plain
 * qualifying-day set. `local_date <= $2` caps the walk at the user's today so
 * a future-dated row (a device clock ahead of itself) can't anchor the streak
 * off tomorrow and read a live run as 0.
 */
function qualifyingDaysSql(includeCoverage: boolean): string {
  return `SELECT local_date FROM workouts
          WHERE user_id = $1 AND local_date <= $2::date
            AND deleted_at IS NULL AND exclusion_reason IS NULL
          GROUP BY local_date
          HAVING SUM(distance) >= ${STREAK_QUALIFYING_MILES}
          ${
            includeCoverage
              ? `UNION
          SELECT local_date FROM streak_coverage
          WHERE user_id = $1 AND local_date <= $2::date`
              : ""
          }`;
}

/**
 * Descending, de-duped list of the user's qualified-or-covered days up to
 * `upTo`. ONE query, however long the history — this feeds the JavaScript
 * walks, which only run for users with a pause on record (elision doesn't
 * express cleanly in SQL). Everyone else is answered by the island queries
 * below without the days ever leaving Postgres.
 */
async function fetchQualifyingDaysDesc(
  userId: string,
  includeCoverage: boolean,
  upTo: string,
): Promise<string[]> {
  const rows = await db.query<{ d: string }>(
    `SELECT to_char(local_date, 'YYYY-MM-DD') AS d
     FROM (${qualifyingDaysSql(includeCoverage)}) q
     ORDER BY local_date DESC`,
    [userId, upTo],
  );
  return rows.map((r) => r.d);
}

// ─── The stored snapshot ───────────────────────────────────────────────────

/** Everything a recompute or a read needs about one user, in ONE row read. */
interface StreakContext {
  userId: string;
  userToday: string;
  enrolled: boolean;
  pauses: PauseInterval[];
  stored: {
    streak: number;
    start: string | null;
    validThrough: string | null;
    /** false = never written by the snapshot code → heal on first read. */
    computed: boolean;
  };
}

async function loadStreakContext(
  userId: string,
): Promise<StreakContext | null> {
  const rows = await db.query<{
    user_today: string;
    enrolled: boolean;
    current_streak: number;
    streak_start_date: string | null;
    streak_valid_through: string | null;
    computed: boolean;
    pauses: PauseInterval[];
  }>(
    `SELECT to_char(${userTodaySql("u")}, 'YYYY-MM-DD') AS user_today,
            (u.streak_features_at IS NOT NULL) AS enrolled,
            u.current_streak,
            to_char(u.streak_start_date, 'YYYY-MM-DD') AS streak_start_date,
            to_char(u.streak_valid_through, 'YYYY-MM-DD') AS streak_valid_through,
            (u.streak_computed_at IS NOT NULL) AS computed,
            COALESCE((
              SELECT json_agg(json_build_object(
                       'started_on', to_char(sp.started_on, 'YYYY-MM-DD'),
                       'resumed_on', to_char(sp.resumed_on, 'YYYY-MM-DD'),
                       'expired', (sp.expired_at IS NOT NULL))
                     ORDER BY sp.started_on DESC)
              FROM streak_pauses sp WHERE sp.user_id = u.user_id
            ), '[]'::json) AS pauses
     FROM users u WHERE u.user_id = $1`,
    [userId],
  );
  const r = rows[0];
  if (!r) return null;
  return {
    userId,
    userToday: r.user_today,
    enrolled: r.enrolled,
    pauses: r.pauses ?? [],
    stored: {
      streak: Number(r.current_streak) || 0,
      start: r.streak_start_date,
      validThrough: r.streak_valid_through,
      computed: r.computed,
    },
  };
}

/** What a recompute produces — the four columns refreshStoredStreak writes. */
export interface StreakSnapshot {
  streak: number;
  /** First and last counted day of the run; undefined at 0. */
  start?: string;
  end?: string;
  /**
   * Last local day this number stands without a recompute. null = frozen by
   * an open pause (never expires) — or nothing to expire, at 0.
   */
  validThrough: string | null;
}

/**
 * The consecutive-days walk, over an already-fetched descending day list:
 * today counts if present but isn't required (yesterday anchors too), stop at
 * the first uncovered miss. A run logged DURING a pause earns nothing — the
 * streak is frozen, not merely protected — so suppressed days are skipped
 * here rather than filtered out of the query, which keeps them in every other
 * total (miles, competitions, the feed all still count them).
 */
function walkCurrent(
  daysDesc: string[],
  anchorToday: string,
  anchorYesterday: string,
  suppress: (d: string) => boolean,
  bridge: (d: string) => boolean,
): { streak: number; start?: string; end?: string } {
  let streak = 0;
  let start: string | undefined;
  let end: string | undefined;
  let expected: string | undefined;
  for (const date of daysDesc) {
    if (suppress(date)) continue;
    if (expected === undefined) {
      if (date !== anchorToday && date !== anchorYesterday)
        return { streak: 0 };
      streak = 1;
      start = date;
      end = date;
    } else if (date === expected) {
      streak++;
      start = date;
    } else {
      break;
    }
    expected = elidePaused(dateStrMinus(date, 1), bridge);
  }
  return { streak, start, end };
}

/** Same walk, but grouping the WHOLE list into runs ("eras"), newest first. */
function walkEras(
  daysDesc: string[],
  anchorToday: string,
  anchorYesterday: string,
  suppress: (d: string) => boolean,
  bridge: (d: string) => boolean,
): StreakEra[] {
  const eras: StreakEra[] = [];
  let open: StreakEra | null = null;
  let expected: string | undefined;
  for (const date of daysDesc) {
    if (suppress(date)) continue;
    if (open !== null && date === expected) {
      open.start_date = date;
      open.length++;
    } else {
      if (open !== null) eras.push(open);
      open = {
        start_date: date,
        end_date: date,
        length: 1,
        is_current: date === anchorToday || date === anchorYesterday,
      };
    }
    expected = elidePaused(dateStrMinus(date, 1), bridge);
  }
  if (open !== null) eras.push(open);
  return eras;
}

/**
 * Until which local day does a streak ending on `end` stand without a new
 * qualifying day? Normally `end + 1` (the yesterday grace). A LIVE pause moves
 * it: days inside a bridging pause don't count as misses, so the run stays
 * valid until the first unpaused day after it — and an OPEN pause has no such
 * day, so the streak is frozen (null). Exactly mirrors how the walk anchors:
 * on day T the run is current iff `end` is the elided today or yesterday.
 */
export function streakValidThrough(
  end: string,
  pauses: PauseInterval[],
): string | null {
  if (pauses.some((p) => p.resumed_on === null && !p.expired)) return null;
  const { bridge } = makePauseGates(pauses);
  let d = dateStrPlus(end, 1);
  for (let i = 0; i < MAX_PAUSE_ELIDE_DAYS; i++) {
    if (!bridge(d)) return d;
    d = dateStrPlus(d, 1);
  }
  return null;
}

async function computeSnapshotWith(
  ctx: StreakContext,
  userToday: string,
): Promise<StreakSnapshot> {
  const includeCoverage = ctx.enrolled && streakFeaturesGloballyEnabled();

  if (ctx.pauses.length === 0) {
    // The common case, answered entirely in Postgres: gaps-and-islands over
    // the qualifying days, keeping the island the NEWEST day belongs to. Under
    // a DESC row numbering the island key must ADD the row number (`d + rn`);
    // consecutive days then share a key. (Subtracting under DESC drifts two
    // days per row and makes every date its own island — the bug that once
    // had streakEndingAt answer 1 for every real streak.)
    const rows = await db.query<{
      len: number;
      start_d: string | null;
      end_d: string | null;
    }>(
      `WITH days AS (${qualifyingDaysSql(includeCoverage)}),
       numbered AS (
         SELECT local_date,
                local_date + (ROW_NUMBER() OVER (ORDER BY local_date DESC))::int AS grp
         FROM days
       ),
       newest AS (SELECT grp FROM numbered ORDER BY local_date DESC LIMIT 1)
       SELECT COUNT(*)::int AS len,
              to_char(MIN(n.local_date), 'YYYY-MM-DD') AS start_d,
              to_char(MAX(n.local_date), 'YYYY-MM-DD') AS end_d
       FROM numbered n JOIN newest ON newest.grp = n.grp`,
      [ctx.userId, userToday],
    );
    const r = rows[0];
    const end = r?.end_d ?? null;
    // Anchor rule, unchanged: the run must reach today or yesterday.
    if (!r || !end || !r.start_d || r.len <= 0)
      return { streak: 0, validThrough: null };
    if (end !== userToday && end !== dateStrMinus(userToday, 1)) {
      return { streak: 0, validThrough: null };
    }
    return {
      streak: Number(r.len),
      start: r.start_d,
      end,
      validThrough: streakValidThrough(end, ctx.pauses),
    };
  }

  // A user with a pause on record: elision is a JavaScript walk, over ONE
  // fetch of their days. The anchor elides too, and it has to: a user who
  // resumes today after a 90-day pause has no qualifying day anywhere near
  // today, so anchoring on the literal today/yesterday would read their
  // 400-day streak as 0 the instant they came back.
  const { suppress, bridge } = makePauseGates(ctx.pauses);
  const anchorToday = elidePaused(userToday, bridge);
  const anchorYesterday = elidePaused(dateStrMinus(anchorToday, 1), bridge);
  const days = await fetchQualifyingDaysDesc(
    ctx.userId,
    includeCoverage,
    userToday,
  );
  const w = walkCurrent(days, anchorToday, anchorYesterday, suppress, bridge);
  if (w.streak <= 0 || !w.end) return { streak: 0, validThrough: null };
  return {
    streak: w.streak,
    start: w.start,
    end: w.end,
    validThrough: streakValidThrough(w.end, ctx.pauses),
  };
}

/**
 * Recompute a user's current streak from their workouts (plus coverage and
 * pauses) WITHOUT writing it. `userToday` overrides the user's derived today —
 * the tests use that to ask "what will this read tomorrow?".
 */
export async function computeStreakSnapshot(
  userId: string,
  userToday?: string,
): Promise<StreakSnapshot> {
  const ctx = await loadStreakContext(userId);
  if (!ctx) return { streak: 0, validThrough: null };
  return computeSnapshotWith(ctx, userToday ?? ctx.userToday);
}

async function persistSnapshot(ctx: StreakContext): Promise<StreakSnapshot> {
  const snap = await computeSnapshotWith(ctx, ctx.userToday);
  const s = ctx.stored;
  const unchanged =
    s.computed &&
    s.streak === snap.streak &&
    s.start === (snap.start ?? null) &&
    s.validThrough === snap.validThrough;
  // Skip the no-op write: the daily reconcile visits every active user, and
  // rewriting an identical row is WAL, index churn (idx_users_current_streak)
  // and a row lock for nothing. longest_streak is already >= streak on an
  // unchanged row because the previous write ratcheted it.
  if (!unchanged) {
    await db.query(
      `UPDATE users
          SET current_streak = $1,
              longest_streak = GREATEST(longest_streak, $1),
              streak_start_date = $2::date,
              streak_valid_through = $3::date,
              streak_computed_at = NOW()
        WHERE user_id = $4`,
      [snap.streak, snap.start ?? null, snap.validThrough, ctx.userId],
    );
  }
  return snap;
}

/**
 * THE writer of users.current_streak (+ start / valid-through / computed-at,
 * and the longest_streak ratchet). Two queries for a user with no pause, three
 * with — regardless of how long the history is. Returns the streak.
 *
 * Call it after ANY mutation of what qualifies (see the header). Callers
 * outside this module go through leaderboardService.refreshCurrentStreak,
 * which is this.
 */
export async function refreshStoredStreak(userId: string): Promise<number> {
  const ctx = await loadStreakContext(userId);
  if (!ctx) return 0;
  return (await persistSnapshot(ctx)).streak;
}

/**
 * The user's current streak as every read path should answer it: the stored
 * snapshot with the calendar decay applied (past `streak_valid_through` it
 * reads 0). ONE row read, no workouts touched — with a single exception: a
 * row the snapshot code has never written (legacy, or a brand-new user) is
 * computed and stored right here, once, so it's never wrong for long.
 */
export async function readStoredStreak(
  userId: string,
): Promise<{ streak: number; start: string | undefined }> {
  const ctx = await loadStreakContext(userId);
  if (!ctx) return { streak: 0, start: undefined };
  if (!ctx.stored.computed) {
    const snap = await persistSnapshot(ctx);
    return { streak: snap.streak, start: snap.start };
  }
  const { streak, start, validThrough } = ctx.stored;
  if (streak <= 0) return { streak: 0, start: undefined };
  if (validThrough !== null && validThrough < ctx.userToday) {
    return { streak: 0, start: undefined };
  }
  return { streak, start: start ?? undefined };
}

/**
 * Hourly: zero every stored streak whose valid-through day has passed in the
 * user's own timezone. ONE statement over the active users — no recompute,
 * because past `streak_valid_through` the answer is 0 by construction (any
 * later qualifying day would have refreshed the row when it landed). The
 * `<= CURRENT_DATE` prefilter is just the cheap bound: a user's today is
 * within a day of the server's, so nothing later can have expired anywhere.
 * Reads already apply this decay themselves; the sweep exists so the
 * leaderboard's `current_streak DESC` index doesn't rank the stale rows.
 */
export async function decayExpiredStreaks(): Promise<number> {
  const rows = await db.query<{ user_id: string }>(
    `UPDATE users u
        SET current_streak = 0,
            streak_start_date = NULL,
            streak_valid_through = NULL,
            streak_computed_at = NOW()
      WHERE u.current_streak > 0
        AND u.streak_valid_through IS NOT NULL
        AND u.streak_valid_through <= CURRENT_DATE
        AND u.streak_valid_through < ${userTodaySql("u")}
      RETURNING u.user_id`,
  );
  return rows.length;
}

/**
 * Compute-and-store every row the snapshot code has never written. Runs once
 * post-listen at boot (the deploy that introduces the columns finds every
 * active user here; a few thousand users is seconds) and hourly as a
 * backstop. Idempotent — after the first pass the set is empty, so it costs
 * one SELECT. Never throws: one bad row must not strand the rest.
 */
export async function healUncomputedStreaks(): Promise<number> {
  const rows = await db.query<{ user_id: string }>(
    `SELECT user_id FROM users
      WHERE streak_computed_at IS NULL AND current_streak > 0
      ORDER BY user_id`,
  );
  let healed = 0;
  for (const { user_id } of rows) {
    try {
      await refreshStoredStreak(user_id);
      healed++;
    } catch (err: any) {
      console.error(
        `[Streaks] heal failed for ${user_id}:`,
        err?.message ?? err,
      );
    }
  }
  return healed;
}

/**
 * Daily safety net: recompute every active user's streak from scratch and
 * write back whatever changed. Catches anything that mutated workouts without
 * calling refreshStoredStreak (a manual data fix, a path someone forgets).
 * With the no-op-write skip it's one or two cheap queries per user.
 */
export async function reconcileAllStreaks(): Promise<{
  checked: number;
  changed: number;
}> {
  const rows = await db.query<{ user_id: string; current_streak: number }>(
    `SELECT user_id, current_streak FROM users WHERE current_streak > 0 ORDER BY user_id`,
  );
  let changed = 0;
  for (const { user_id, current_streak } of rows) {
    try {
      const after = await refreshStoredStreak(user_id);
      if (Number(current_streak) !== after) changed++;
    } catch (err: any) {
      console.error(
        `[Streaks] Failed to reconcile streak for ${user_id}:`,
        err?.message ?? err,
      );
    }
  }
  return { checked: rows.length, changed };
}

/**
 * Compute-only streak for a given today (coverage + pauses applied). Kept for
 * callers that want the live number without touching the stored row.
 */
export async function computeCoveredStreak(
  userId: string,
  userToday: string,
): Promise<{ streak: number; start: string | undefined }> {
  const snap = await computeStreakSnapshot(userId, userToday);
  return { streak: snap.streak, start: snap.start };
}

export interface StreakEra {
  start_date: string; // YYYY-MM-DD
  end_date: string; // YYYY-MM-DD
  length: number;
  is_current: boolean;
}

/**
 * The user's ENTIRE qualified-or-covered day history grouped into consecutive
 * runs ("eras"), newest first. Covered days count exactly when the live
 * streak counts them (same enrollment + env gate), so the current era's
 * length always agrees with the stored streak — un-enrolled users get the
 * plain qualifying-day grouping. `is_current` uses the same today/yesterday
 * grace, and only the newest era can carry it.
 *
 * One island query for users without a pause; the JavaScript walk over one
 * fetch for users with one. Pauses are applied unconditionally, NOT behind the
 * kill switch: the live streak still bridges open pauses with the switch on,
 * and this must never call the current era broken while /streak calls it
 * intact — the same user, two answers.
 */
export async function computeStreakEras(
  userId: string,
  userToday: string,
): Promise<{ eras: StreakEra[]; longest: number }> {
  const ctx = await loadStreakContext(userId);
  if (!ctx) return { eras: [], longest: 0 };
  const includeCoverage = ctx.enrolled && streakFeaturesGloballyEnabled();
  const { suppress, bridge } = makePauseGates(ctx.pauses);
  const anchorToday = elidePaused(userToday, bridge);
  const anchorYesterday = elidePaused(dateStrMinus(anchorToday, 1), bridge);

  let eras: StreakEra[];
  if (ctx.pauses.length === 0) {
    // ASC numbering pairs with `d - rn` (the mirror of the DESC rule above).
    const rows = await db.query<{
      start_date: string;
      end_date: string;
      length: number;
    }>(
      `WITH days AS (${qualifyingDaysSql(includeCoverage)}),
       numbered AS (
         SELECT local_date,
                local_date - (ROW_NUMBER() OVER (ORDER BY local_date ASC))::int AS grp
         FROM days
       )
       SELECT to_char(MIN(local_date), 'YYYY-MM-DD') AS start_date,
              to_char(MAX(local_date), 'YYYY-MM-DD') AS end_date,
              COUNT(*)::int AS length
       FROM numbered
       GROUP BY grp
       ORDER BY MAX(local_date) DESC`,
      [userId, userToday],
    );
    eras = rows.map((r) => ({
      start_date: r.start_date,
      end_date: r.end_date,
      length: Number(r.length),
      is_current: r.end_date === anchorToday || r.end_date === anchorYesterday,
    }));
  } else {
    eras = walkEras(
      await fetchQualifyingDaysDesc(userId, includeCoverage, userToday),
      anchorToday,
      anchorYesterday,
      suppress,
      bridge,
    );
  }

  let longest = 0;
  for (const era of eras) {
    if (era.length > longest) longest = era.length;
  }
  return { eras, longest };
}

/**
 * streakEndingAt for the rare user who has an injury pause in their history.
 *
 * The SQL below is a gaps-and-islands over raw dates, and elision doesn't
 * express cleanly there — you'd need a per-row count of paused days to compress
 * the date axis before islanding. Rather than complicate a query every break
 * stamp runs, users WITHOUT pauses keep the untouched SQL (byte-identical, no
 * new risk for effectively everyone) and only paused users pay for this walk.
 * Coverage is unconditional here, as in the SQL path: this only runs in token
 * contexts (break stamps, pause freezing), i.e. for enrolled users.
 */
async function streakEndingAtElided(
  userId: string,
  endDate: string,
  suppress: (d: string) => boolean,
  bridge: (d: string) => boolean,
): Promise<number> {
  const days = await fetchQualifyingDaysDesc(userId, true, endDate);

  let streak = 0;
  let expected: string | undefined;
  for (const date of days) {
    if (suppress(date)) continue;
    if (expected === undefined) {
      if (date !== endDate) return 0; // endDate itself must qualify
      streak = 1;
    } else if (date !== expected) {
      break;
    } else {
      streak++;
    }
    expected = elidePaused(dateStrMinus(date, 1), bridge);
  }
  return streak;
}

/**
 * Length of the consecutive qualified-or-covered run ENDING exactly at
 * `endDate` (0 when endDate itself doesn't qualify). Used for the
 * prior-streak stamped on a break event — i.e. what an assist would restore.
 *
 * Gaps-and-islands: the island key must move in the OPPOSITE direction to the
 * row numbering, so a DESC walk ADDS the row number (`d + rn`) — consecutive
 * days then share a key. Subtracting under a DESC walk (`d - rn`, which this
 * shipped with) makes the key drift by two days per row, so every date lands
 * in its OWN island and the answer is always exactly 1. Every Streak Assist
 * therefore advertised "back to 2 days" no matter how long the real run was,
 * and `recordBreak`'s `prior >= MIN_NOTIFY_PRIOR_STREAK` gate never opened, so
 * the "their streak just broke, you can save it" push never fired at all.
 */
export async function streakEndingAt(
  userId: string,
  endDate: string,
): Promise<number> {
  const pauses = await fetchPauseIntervals(userId);
  if (pauses.length > 0) {
    const { suppress, bridge } = makePauseGates(pauses);
    return streakEndingAtElided(userId, endDate, suppress, bridge);
  }

  const rows = await db.query<{ len: number; max_d: string }>(
    `WITH days AS (
       SELECT local_date FROM workouts
       WHERE user_id = $1 AND local_date <= $2::date
         AND deleted_at IS NULL AND exclusion_reason IS NULL
       GROUP BY local_date HAVING SUM(distance) >= ${STREAK_QUALIFYING_MILES}
       UNION
       SELECT local_date FROM streak_coverage
       WHERE user_id = $1 AND local_date <= $2::date
     ),
     numbered AS (
       SELECT local_date,
              local_date + (ROW_NUMBER() OVER (ORDER BY local_date DESC))::int AS grp
       FROM days
     )
     SELECT COUNT(*)::int AS len,
            to_char(MAX(local_date), 'YYYY-MM-DD') AS max_d
     FROM numbered
     WHERE grp = (
       -- The island the MOST RECENT day belongs to. Explicitly ordered: a bare
       -- LIMIT 1 leaned on the window sort leaking through, which is not a
       -- guarantee Postgres makes.
       SELECT grp FROM numbered ORDER BY local_date DESC LIMIT 1
     )`,
    [userId, endDate],
  );
  const row = rows[0];
  if (!row || !row.max_d) return 0;
  return row.max_d === endDate ? Number(row.len) : 0;
}
