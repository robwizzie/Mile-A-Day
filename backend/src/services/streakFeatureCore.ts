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

/**
 * Must this user's streak skip the LEGACY walk? True when token coverage is
 * live for them, and — independently — whenever they have any pause on record.
 *
 * The pause half is not an optimization, it's a safety interlock. The legacy
 * loop knows nothing about streak_pauses, so if STREAK_FEATURES_DISABLED were
 * flipped during an incident, every injured user would fall into it and
 * refreshCurrentStreak (the ONLY writer of users.current_streak, also driven by
 * a 6-hourly cron) would persist their frozen streak as BROKEN. That write is
 * not recoverable, and it would come from the switch whose entire purpose is to
 * be safe to flip. Killing the tokens must never un-bridge a pause.
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
 * enrolled) — those users' streaks are computed by the byte-identical legacy
 * loop that ignores coverage entirely, so reporting covered days would explain
 * a save that never happened.
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

/**
 * Descending, de-duped stream over the UNION of the user's qualifying workout
 * days and the given covered days (YYYY-MM-DD strings). Pass coverage=[] and
 * the stream degenerates to the plain qualifying-day sequence — byte-identical
 * input to the legacy walks. Extracted verbatim from computeCoveredStreak so
 * every consumer (active streak, streak eras) walks THE same stream; per the
 * house rule, streak recomputes must never fork this.
 */
export function mergedQualifyingDayStream(
  userId: string,
  coverage: string[], // DESC
): { next: () => Promise<string | undefined> } {
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
  let page: { local_date: string }[] | null = null;
  let pi = 0; // cursor into page
  let ci = 0; // cursor into coverage
  let last: string | undefined;

  const next = async (): Promise<string | undefined> => {
    if (page === null) {
      page = await db.query(qualifyingDaysQuery, [userId, LIMIT, 0]);
    }
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

  return { next };
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
  // Coverage is gated INSIDE rather than assumed by the caller, because this
  // walk is now also the path for a paused user whose token coverage is switched
  // off — see needsFeatureWalk. Pauses are always applied; tokens only when live.
  const coverage = (await coverageActiveFor(userId))
    ? await fetchCoverageDates(userId) // DESC
    : [];
  const { suppress, bridge } = makePauseGates(
    await fetchPauseIntervals(userId),
  );
  // The anchor elides too, and it has to: a user who resumes today after a
  // 90-day pause has no qualifying day anywhere near today, so anchoring on the
  // literal today/yesterday would read their 400-day streak as 0 the instant
  // they came back. Anchoring on the last day that COUNTS makes the pause
  // invisible to the walk from both ends.
  const anchorToday = elidePaused(userToday, bridge);
  const anchorYesterday = elidePaused(dateStrMinus(anchorToday, 1), bridge);
  const { next } = mergedQualifyingDayStream(userId, coverage);

  let streak = 0;
  let streakStartDay: string | undefined;
  let expectedDate: string | undefined;

  while (true) {
    const date = await next();
    if (date === undefined) break;
    // A run logged DURING a pause earns nothing — the streak is frozen, not
    // merely protected. Skipping here (rather than filtering the query) keeps
    // the day in every other total: miles, competitions and the feed all still
    // count it, because only the streak is paused.
    if (suppress(date)) continue;

    if (expectedDate === undefined) {
      if (date !== anchorToday && date !== anchorYesterday) {
        return { streak: 0, start: undefined };
      }
      streak = 1;
      streakStartDay = date;
      expectedDate = elidePaused(dateStrMinus(date, 1), bridge);
    } else if (date === expectedDate) {
      streak++;
      streakStartDay = date;
      expectedDate = elidePaused(dateStrMinus(date, 1), bridge);
    } else {
      return { streak, start: streakStartDay };
    }
  }

  return { streak, start: streakStartDay };
}

export interface StreakEra {
  start_date: string; // YYYY-MM-DD
  end_date: string; // YYYY-MM-DD
  length: number;
  is_current: boolean;
}

/**
 * The user's ENTIRE qualified-or-covered day history grouped into consecutive
 * runs ("eras"), newest first. Covered days count exactly when the live walks
 * would count them (same enrollment + env gate via coverageActiveFor), so the
 * current era's length always agrees with getActiveStreak /
 * refreshCurrentStreak — un-enrolled users get the plain qualifying-day
 * grouping, legacy parity. `is_current` uses the walks' today/yesterday grace,
 * and by descending construction only the first era can carry it.
 */
export async function computeStreakEras(
  userId: string,
  userToday: string,
): Promise<{ eras: StreakEra[]; longest: number }> {
  const active = await coverageActiveFor(userId);
  const coverage = active ? await fetchCoverageDates(userId) : [];
  // Pauses are fetched unconditionally, NOT behind `active`. With the kill
  // switch on, the live walks still bridge open pauses (needsFeatureWalk), so
  // gating this on coverage would make /streak-eras call the current era broken
  // while the streak endpoint calls it intact — the same user, two answers.
  const { suppress, bridge } = makePauseGates(await fetchPauseIntervals(userId));
  const { next } = mergedQualifyingDayStream(userId, coverage);
  // Same elided anchor as computeCoveredStreak, so the current era's length
  // keeps agreeing with getActiveStreak across a pause (house rule: the walks
  // must never disagree about the live number).
  const anchorToday = elidePaused(userToday, bridge);
  const anchorYesterday = elidePaused(dateStrMinus(anchorToday, 1), bridge);

  const eras: StreakEra[] = [];
  let open: StreakEra | null = null;
  let expected: string | undefined;

  while (true) {
    const date = await next();
    if (date === undefined) break;
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

  let longest = 0;
  for (const era of eras) {
    if (era.length > longest) longest = era.length;
  }
  return { eras, longest };
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
/**
 * streakEndingAt for the rare user who has an injury pause in their history.
 *
 * The SQL below is a gaps-and-islands over raw dates, and elision doesn't
 * express cleanly there — you'd need a per-row count of paused days to compress
 * the date axis before islanding. Rather than complicate a query every break
 * stamp runs, users WITHOUT pauses keep the untouched SQL (byte-identical, no
 * new risk for effectively everyone) and only paused users pay for this walk.
 */
async function streakEndingAtElided(
  userId: string,
  endDate: string,
  suppress: (d: string) => boolean,
  bridge: (d: string) => boolean,
): Promise<number> {
  const coverage = await fetchCoverageDates(userId);
  const { next } = mergedQualifyingDayStream(userId, coverage);

  let streak = 0;
  let expected: string | undefined;
  while (true) {
    const date = await next();
    if (date === undefined) break;
    if (date > endDate) continue; // stream starts at the newest day
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
       GROUP BY local_date HAVING SUM(distance) >= 0.95
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
