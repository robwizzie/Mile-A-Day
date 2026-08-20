import { PostgresService } from "./DbService.js";
import {
  dateStrMinus,
  dateStrPlus,
  fetchPauseIntervals,
  getStreakFeatureRow,
  streakEndingAt,
  streakFeaturesGloballyEnabled,
} from "./streakFeatureCore.js";
import { refreshCurrentStreak } from "./leaderboardService.js";
import { BadRequestError } from "../errors/Errors.js";

const db = PostgresService.getInstance();

/**
 * Injury pause ("Recovery Mode") — the long-absence counterpart to the
 * single-day tokens (Double Down / Streak Save / Streak Assist).
 *
 * An injury is unfalsifiable from workout data: nothing in HealthKit
 * distinguishes a torn ACL from a cruise. So this feature does NOT try to
 * verify anything (asking would also mean storing health-condition data). It
 * relies on a cost structure only a real injury would accept:
 *
 *   - you must have a 90-day streak to have anything worth pausing,
 *   - the pause runs a MINIMUM of 30 days, so it's useless for a long weekend,
 *   - and you can't pause again until you've rebuilt 90 consecutive days.
 *
 * Worst case someone buys one two-week holiday a year and wears a public
 * "injured" badge for a month to get it. That ceiling is deliberate and
 * acceptable; airtight is not reachable without verification.
 */

/** Streak required before a pause can be started. */
export const MIN_STREAK_TO_PAUSE = 90;
/** How far back a pause may be dated — an injury happens before the paperwork. */
export const MAX_BACKDATE_DAYS = 7;
/** A pause cannot be ended before this many days have elapsed. */
export const MIN_PAUSE_DAYS = 30;
/**
 * Hard ceiling. Chosen from time-to-walk-a-mile (this app counts WALKS, so the
 * bar is walking, not running): ACL reconstruction 8-12 weeks, broken ankle
 * 12-16 weeks, Achilles rupture 4-6 months. 180 days covers ~85-90% of
 * realistic injuries with room to spare, and stops a pause becoming a
 * permanent freeze that parks a stale streak on friends' leaderboards forever.
 */
export const MAX_PAUSE_DAYS = 180;
/** Consecutive days that must be rebuilt after a pause before the next one. */
export const REEARN_DAYS = 90;

/** Emergency brake, fail-open like the rest of the streak features. */
export function injuryPauseEnabled(): boolean {
  return (
    streakFeaturesGloballyEnabled() &&
    process.env.INJURY_PAUSE_DISABLED !== "true"
  );
}

export interface ActivePause {
  id: string;
  started_on: string;
  frozen_streak: number;
  /** Days elapsed including today, i.e. what the UI prints as "Paused N days". */
  paused_days: number;
  /** True once MIN_PAUSE_DAYS has elapsed and the user may resume. */
  can_end: boolean;
  /** Local date the 180-day cap will expire this pause. */
  expires_on: string;
}

export interface InjuryPauseStatus {
  active: ActivePause | null;
  /** Can the user START a pause right now? */
  eligible: boolean;
  /** Machine-readable reason when `eligible` is false. */
  reason:
    | null
    | "not_enrolled"
    | "already_paused"
    | "streak_too_short"
    | "rebuilding";
  /** Days rebuilt since the last pause, for "62 / 90 until you can pause again". */
  reearn_progress: number;
  reearn_target: number;
  min_streak: number;
  min_days: number;
  max_days: number;
  max_backdate_days: number;
}

/** This user's local calendar date, from their most recent workout's offset. */
async function getLocalToday(userId: string): Promise<string> {
  const rows = await db.query<{ user_today: string }>(
    `SELECT to_char(
       (NOW() + (COALESCE(
         (SELECT timezone_offset FROM workouts WHERE user_id = $1
           ORDER BY device_end_date DESC LIMIT 1), 0
       ) || ' minutes')::interval)::date, 'YYYY-MM-DD') AS user_today`,
    [userId],
  );
  return rows[0].user_today;
}

/**
 * Parse YYYY-MM-DD to a UTC epoch, rejecting dates that don't exist.
 *
 * Date.UTC takes a ZERO-BASED month, so the obvious `Date.UTC(y, m, d)` is
 * wrong by a month. That mostly hides — both ends of a span shift together and
 * the difference still comes out right — until a day-31 overflow normalizes one
 * end and not the other, at which point "Jan 31 to Feb 1" measures as NEGATIVE
 * days and a user is told their 30-day minimum isn't up.
 *
 * The round-trip check also rejects calendar-invalid input like 2026-02-31,
 * which a shape-only regex happily accepts and JS would silently roll into March.
 */
function parseIsoDateUtc(s: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const [y, m, d] = s.split("-").map(Number);
  const t = Date.UTC(y, m - 1, d);
  const dt = new Date(t);
  if (
    dt.getUTCFullYear() !== y ||
    dt.getUTCMonth() !== m - 1 ||
    dt.getUTCDate() !== d
  ) {
    return null;
  }
  return t;
}

/** True for a real calendar date in YYYY-MM-DD form. */
export function isValidIsoDate(s: unknown): s is string {
  return typeof s === "string" && parseIsoDateUtc(s) !== null;
}

/** Whole days from `from` to `to` inclusive of both ends. */
function daysBetweenInclusive(from: string, to: string): number {
  const a = parseIsoDateUtc(from);
  const b = parseIsoDateUtc(to);
  if (a === null || b === null) throw new BadRequestError("invalid_started_on");
  return Math.floor((b - a) / 86400000) + 1;
}

async function getActivePauseRow(userId: string): Promise<{
  id: string;
  started_on: string;
  frozen_streak: number;
} | null> {
  const rows = await db.query<{
    id: string;
    started_on: string;
    frozen_streak: number;
  }>(
    `SELECT id, to_char(started_on, 'YYYY-MM-DD') AS started_on, frozen_streak
       FROM streak_pauses
      WHERE user_id = $1 AND resumed_on IS NULL AND expired_at IS NULL`,
    [userId],
  );
  return rows[0] ?? null;
}

/**
 * Qualifying days the user has banked since their last pause ended — the
 * re-earn meter. Counted from `resumed_on` rather than read off the streak,
 * because the streak BRIDGES the pause: a returning user's streak start date
 * is still the pre-injury one, so it can't tell you how much they've rebuilt.
 */
async function reearnProgress(
  userId: string,
  currentStreak: number,
  today: string,
): Promise<number> {
  const rows = await db.query<{ resumed_on: string | null }>(
    `SELECT to_char(resumed_on, 'YYYY-MM-DD') AS resumed_on
       FROM streak_pauses
      WHERE user_id = $1 AND resumed_on IS NOT NULL
      ORDER BY resumed_on DESC LIMIT 1`,
    [userId],
  );
  const resumedOn = rows[0]?.resumed_on;
  if (!resumedOn) return REEARN_DAYS; // never paused — nothing to re-earn
  if (currentStreak <= 0) return 0;

  // The rule is 90 CONSECUTIVE days, so this must not be a count of qualifying
  // dates since the resume — 90 scattered days across half a year would pass
  // that and shouldn't. Clamping the live streak to the window since the resume
  // gives the consecutive answer for free: the streak is consecutive by
  // construction, so whichever of the two is smaller IS the rebuilt run.
  // (The streak alone can't answer it — it BRIDGES the pause, so a returning
  // user's streak still counts all their pre-injury days.)
  const sinceResume = daysBetweenInclusive(resumedOn, today);
  return Math.max(0, Math.min(currentStreak, sinceResume));
}

/**
 * The streak this user could actually freeze right now — i.e. exactly what
 * startInjuryPause would compute for the best start date available to them.
 *
 * The run that matters is the one ending on their LAST qualifying day, and it's
 * only reachable if a pause starting the day after it still falls inside
 * the backdate window.
 */
async function bestStartableStreak(
  userId: string,
  today: string,
): Promise<number> {
  // Unions streak_coverage the same way streakEndingAt does. A day carried by a
  // Streak Save / Double Down / Assist is a streak day with no workout row, so
  // scanning workouts alone would call a token-covered user's last day older
  // than it is and hide the CTA that POST would have honoured.
  const rows = await db.query<{ last_day: string | null }>(
    `SELECT to_char(MAX(local_date), 'YYYY-MM-DD') AS last_day FROM (
       SELECT local_date FROM workouts
        WHERE user_id = $1 AND local_date <= $2::date
          AND deleted_at IS NULL AND exclusion_reason IS NULL
        GROUP BY local_date HAVING SUM(distance) >= 0.95
       UNION
       SELECT local_date FROM streak_coverage
        WHERE user_id = $1 AND local_date <= $2::date
     ) d`,
    [userId, today],
  );
  const lastDay = rows[0]?.last_day;
  if (!lastDay) return 0;

  // The best legal start is the day after their last qualifying day, clamped to
  // today because a pause cannot begin in the future. Deriving the answer from
  // that start — rather than from users.current_streak — is what keeps GET and
  // POST agreeing: on the day a user's streak first reaches 90, a pause started
  // today would freeze the run ending YESTERDAY (89), so `eligible` must say no
  // rather than advertise a button that 400s.
  const bestStart = lastDay >= today ? today : dateStrPlus(lastDay, 1);
  if (daysBetweenInclusive(bestStart, today) - 1 > MAX_BACKDATE_DAYS) return 0;

  return streakEndingAt(userId, dateStrMinus(bestStart, 1));
}

export async function getInjuryPauseStatus(
  userId: string,
): Promise<InjuryPauseStatus> {
  const limits = {
    reearn_target: REEARN_DAYS,
    min_streak: MIN_STREAK_TO_PAUSE,
    min_days: MIN_PAUSE_DAYS,
    max_days: MAX_PAUSE_DAYS,
    max_backdate_days: MAX_BACKDATE_DAYS,
  };

  const row = await getStreakFeatureRow(userId);
  const enrolled = !!row?.streak_features_at;
  const active = await getActivePauseRow(userId);

  if (active) {
    const today = await getLocalToday(userId);
    const pausedDays = daysBetweenInclusive(active.started_on, today);
    return {
      active: {
        id: active.id,
        started_on: active.started_on,
        frozen_streak: active.frozen_streak,
        paused_days: pausedDays,
        can_end: pausedDays >= MIN_PAUSE_DAYS,
        expires_on: dateStrPlus(active.started_on, MAX_PAUSE_DAYS - 1),
      },
      eligible: false,
      reason: "already_paused",
      reearn_progress: 0,
      ...limits,
    };
  }

  const today = await getLocalToday(userId);
  const streak = Number(row?.current_streak ?? 0);
  const progress = await reearnProgress(userId, streak, today);
  // Must mirror what startInjuryPause would actually accept, not just today's
  // number. An injury has usually already cost a day or two by the time the
  // user opens the app, so current_streak may read 0 while a backdated start
  // would still succeed — reporting `streak_too_short` there would hide the
  // button from precisely the person the feature exists for.
  const startable = await bestStartableStreak(userId, today);

  // "rebuilding" is checked FIRST because it's the more specific answer and the
  // two overlap constantly: someone who just came back from a pause also has a
  // short freezable run, and telling them their streak is too short invites
  // them to go and fix a thing that isn't the blocker. Users who have never
  // paused can't hit this branch at all — reearnProgress returns the full
  // target for them.
  let reason: InjuryPauseStatus["reason"] = null;
  if (!enrolled) reason = "not_enrolled";
  else if (progress < REEARN_DAYS) reason = "rebuilding";
  else if (startable < MIN_STREAK_TO_PAUSE) reason = "streak_too_short";

  return {
    active: null,
    eligible: reason === null && injuryPauseEnabled(),
    reason,
    reearn_progress: Math.min(progress, REEARN_DAYS),
    ...limits,
  };
}

/**
 * Open a pause, optionally backdated up to MAX_BACKDATE_DAYS.
 *
 * Backdating is what makes the feature work at all for its actual use case: an
 * injury happens suddenly and the person is at the hospital, not in a running
 * app. Without it the streak is already gone by the time they can press the
 * button. That also means the eligibility check runs against the streak as it
 * stood the day BEFORE the injury — not today's, which may already be broken.
 */
export async function startInjuryPause(
  userId: string,
  startedOn?: string,
): Promise<InjuryPauseStatus> {
  if (!injuryPauseEnabled()) throw new BadRequestError("injury_pause_disabled");

  const row = await getStreakFeatureRow(userId);
  if (!row?.streak_features_at) throw new BadRequestError("not_enrolled");

  const today = await getLocalToday(userId);
  const start = startedOn ?? today;

  // Round-trip validated, not just shape-matched: 2026-02-31 passes a regex and
  // would otherwise roll into March on the way to the ::date cast.
  if (!isValidIsoDate(start)) {
    throw new BadRequestError("invalid_started_on");
  }
  if (start > today) throw new BadRequestError("started_on_in_future");
  // MAX_BACKDATE_DAYS is an OFFSET, not an inclusive day count: "up to a week
  // back" means today - 7 is allowed, which spans 8 calendar days.
  if (daysBetweenInclusive(start, today) - 1 > MAX_BACKDATE_DAYS) {
    throw new BadRequestError("backdate_too_far");
  }
  if (await getActivePauseRow(userId)) {
    throw new BadRequestError("already_paused");
  }
  const streak = Number(row.current_streak ?? 0);
  if ((await reearnProgress(userId, streak, today)) < REEARN_DAYS) {
    throw new BadRequestError("rebuilding");
  }

  // The streak as it stood the day before the injury. This is the honest
  // number to freeze AND the right thing to gate on, because a backdated start
  // may sit behind a break that has already been stamped.
  const frozen = await streakEndingAt(userId, dateStrMinus(start, 1));
  if (frozen < MIN_STREAK_TO_PAUSE) {
    throw new BadRequestError("streak_too_short");
  }

  const client = await db.getClient();
  try {
    await client.query("BEGIN");
    await client.query(
      `INSERT INTO streak_pauses (user_id, started_on, frozen_streak)
       VALUES ($1, $2::date, $3)`,
      [userId, start, frozen],
    );
    // A backdated pause reaches over days that may already have been stamped
    // as a break by the morning sweep. Those events are what drive the "your
    // streak ended" card and the assist-opportunity pushes, so leaving them
    // would tell the user their streak both survived and didn't.
    await client.query(
      `DELETE FROM streak_events
        WHERE user_id = $1 AND kind = 'break' AND local_date >= $2::date`,
      [userId, start],
    );
    await client.query("COMMIT");
  } catch (err: any) {
    await client.query("ROLLBACK");
    // Two devices can both clear the pre-check and race to INSERT; the partial
    // unique index is what actually enforces one active pause. Losing that race
    // means the pause EXISTS, so it's the already_paused answer, not a 500.
    if (err?.code === "23505") {
      throw new BadRequestError("already_paused");
    }
    throw err;
  } finally {
    client.release();
  }

  // Re-derive immediately so the number the client reads back is the frozen
  // one, not the pre-pause value the sweep may already have zeroed.
  await refreshCurrentStreak(userId);
  return getInjuryPauseStatus(userId);
}

/**
 * Close a pause. `resumed_on` is set to the user's local today and the interval
 * is half-open, so today counts for them straight away — a user who ends their
 * pause and walks a mile the same day extends the streak rather than losing it.
 */
export async function endInjuryPause(
  userId: string,
): Promise<InjuryPauseStatus> {
  const active = await getActivePauseRow(userId);
  if (!active) throw new BadRequestError("not_paused");

  const today = await getLocalToday(userId);
  const pausedDays = daysBetweenInclusive(active.started_on, today);
  if (pausedDays < MIN_PAUSE_DAYS) {
    throw new BadRequestError("minimum_not_reached");
  }

  // Past the cap, ending is an EXPIRY, not a resume. The hourly sweep normally
  // gets here first, but if it has lagged or failed, resuming without
  // `expired_at` would leave an over-cap gap bridged forever — the one path
  // that could turn the 180-day ceiling into an unbounded freeze.
  if (pausedDays > MAX_PAUSE_DAYS) {
    await db.query(
      `UPDATE streak_pauses
          SET resumed_on = started_on + $1::int, expired_at = NOW()
        WHERE id = $2 AND resumed_on IS NULL`,
      [MAX_PAUSE_DAYS, active.id],
    );
    await refreshCurrentStreak(userId);
    return getInjuryPauseStatus(userId);
  }

  await db.query(
    `UPDATE streak_pauses SET resumed_on = $1::date
      WHERE id = $2 AND resumed_on IS NULL`,
    [today, active.id],
  );
  await refreshCurrentStreak(userId);
  return getInjuryPauseStatus(userId);
}

/**
 * Expire pauses that have run past the cap. Called from the hourly streak
 * sweep rather than its own cron — there is nothing time-critical here and a
 * pause is only ever a few hours "over".
 *
 * Expiring sets resumed_on (so the row stops being active) AND expired_at (so
 * it stops BRIDGING). The elided days revert to ordinary misses, the streak
 * ends, and longest_streak keeps the frozen value it ratcheted to while the
 * pause was live — "converts to longest streak", exactly.
 */
export async function expirePausesPastCap(): Promise<number> {
  if (!injuryPauseEnabled()) return 0;
  const rows = await db.query<{ user_id: string }>(
    `UPDATE streak_pauses sp
        SET resumed_on = sp.started_on + $1::int, expired_at = NOW()
      WHERE sp.resumed_on IS NULL
        AND sp.expired_at IS NULL
        AND sp.started_on + $1::int <= (
          NOW() + (COALESCE((
            SELECT timezone_offset FROM workouts w
             WHERE w.user_id = sp.user_id
             ORDER BY device_end_date DESC LIMIT 1), 0) || ' minutes')::interval
        )::date
      RETURNING sp.user_id`,
    [MAX_PAUSE_DAYS],
  );
  for (const { user_id } of rows) {
    // Best-effort: one user's bad row must not strand the rest of the sweep.
    await refreshCurrentStreak(user_id).catch((e: any) =>
      console.error(
        `[InjuryPause] refresh after expiry failed for ${user_id}:`,
        e?.message,
      ),
    );
  }
  return rows.length;
}

/**
 * Users among `userIds` who are currently paused, for the friend-facing
 * "injured" badge. Batched because every friends-list read needs it.
 */
export async function pausedUserIds(userIds: string[]): Promise<Set<string>> {
  if (userIds.length === 0) return new Set();
  const rows = await db.query<{ user_id: string }>(
    `SELECT DISTINCT user_id FROM streak_pauses
      WHERE user_id = ANY($1::text[]) AND resumed_on IS NULL AND expired_at IS NULL`,
    [userIds],
  );
  return new Set(rows.map((r) => r.user_id));
}

/**
 * True when this user has an open pause.
 *
 * Deliberately does NOT consult the kill switch, and neither does the elision
 * in streakFeatureCore. INJURY_PAUSE_DISABLED stops new pauses being STARTED;
 * it must never un-bridge the ones already open. If it did, flipping the
 * switch during an incident would hand every injured user to the morning
 * sweep, which would stamp a real break and destroy exactly the streaks this
 * feature exists to protect — an un-recoverable write, from a switch whose
 * whole purpose is to be safe to flip.
 */
export async function isPaused(userId: string): Promise<boolean> {
  const intervals = await fetchPauseIntervals(userId);
  return intervals.some((p) => p.resumed_on === null);
}
