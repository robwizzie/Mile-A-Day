import { PostgresService } from "./DbService.js";
import { BadRequestError } from "../errors/Errors.js";
import { createSession, validateGoal } from "./buddySessionService.js";
import { logError } from "./errorLogService.js";
import type { BuddyActivityType, BuddyMode } from "../types/buddy.js";

const db = PostgresService.getInstance();

/**
 * Recurring buddy walks — "us, 6pm, weekdays".
 *
 * The feature's whole point is a habit, and until now every occurrence meant
 * rebuilding the lobby and re-inviting from scratch. A routine is a TEMPLATE,
 * not a session: the cron spawns a real `buddy_sessions` row from it shortly
 * before each due time and hands off to machinery that already exists —
 * `promoteDueScheduledSessions` starts it on the minute, the heads-up push
 * fires, the lobby is the lobby. Nothing downstream knows a routine was
 * involved.
 *
 * Time is LOCAL wall-clock minutes plus an IANA zone, never a stored instant:
 * "6pm on weekdays" has to survive DST, and a timestamp would drift an hour
 * twice a year.
 */

/** Spawn this far before the start, so invitees get a real heads-up. */
const SPAWN_LEAD_MINUTES = 15;

/**
 * ...and still spawn this far AFTER, so a cron outage doesn't silently skip a
 * day. A session created past its own start time is simply promoted at once by
 * the existing lazy check, which is the correct outcome — late is better than
 * never for something someone is standing outside waiting for.
 */
const SPAWN_GRACE_MINUTES = 10;

/** Per-user cap. A routine list is a habit, not a calendar. */
const MAX_ROUTINES_PER_USER = 10;

export interface BuddyRecurringWalk {
  id: string;
  host_user_id: string;
  mode: string;
  goal_value: number | null;
  activity_type: string;
  invite_user_ids: string[];
  days_of_week: number[];
  minutes_of_day: number;
  timezone: string;
  is_active: boolean;
  last_spawned_date: string | null;
}

export interface RecurringWalkInput {
  mode: BuddyMode;
  goalValue?: number | null;
  activityType: BuddyActivityType;
  inviteUserIds?: string[];
  daysOfWeek: number[];
  minutesOfDay: number;
  timezone: string;
}

/**
 * Reject anything Postgres would refuse to use as a time zone.
 *
 * The value reaches SQL as `NOW() AT TIME ZONE tz`, and an unknown zone raises
 * at QUERY time — inside the cron, where it would abort the sweep for every
 * OTHER user's routine too. Validated once at write instead.
 */
function assertValidTimezone(tz: unknown): string {
  if (typeof tz !== "string" || tz.length === 0 || tz.length > 64) {
    throw new BadRequestError("invalid_timezone");
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
  } catch {
    throw new BadRequestError("invalid_timezone");
  }
  return tz;
}

/** 0=Sunday … 6=Saturday, deduped and sorted. At least one day. */
function normalizeDays(raw: unknown): number[] {
  if (!Array.isArray(raw)) throw new BadRequestError("invalid_days");
  const days = [
    ...new Set(
      raw
        .map((d) => Number(d))
        .filter((d) => Number.isInteger(d) && d >= 0 && d <= 6),
    ),
  ].sort((a, b) => a - b);
  if (days.length === 0) throw new BadRequestError("invalid_days");
  return days;
}

function normalizeMinutes(raw: unknown): number {
  const minutes = Number(raw);
  if (!Number.isInteger(minutes) || minutes < 0 || minutes > 1439) {
    throw new BadRequestError("invalid_time");
  }
  return minutes;
}

export async function listRecurringWalks(
  userId: string,
): Promise<BuddyRecurringWalk[]> {
  return db.query<BuddyRecurringWalk>(
    `SELECT id, host_user_id, mode, goal_value, activity_type, invite_user_ids,
            days_of_week, minutes_of_day, timezone, is_active,
            to_char(last_spawned_date, 'YYYY-MM-DD') AS last_spawned_date
       FROM buddy_recurring_walks
      WHERE host_user_id = $1
      ORDER BY minutes_of_day ASC, created_at ASC`,
    [userId],
  );
}

export async function createRecurringWalk(
  userId: string,
  input: RecurringWalkInput,
): Promise<BuddyRecurringWalk> {
  const days = normalizeDays(input.daysOfWeek);
  const minutes = normalizeMinutes(input.minutesOfDay);
  const timezone = assertValidTimezone(input.timezone);
  // The same rule create/PATCH use, so a routine can never spawn a session the
  // session endpoint itself would reject.
  const goalValue = validateGoal(input.mode, input.goalValue ?? null);

  const existing = await db.query<{ n: number }>(
    `SELECT COUNT(*)::int AS n FROM buddy_recurring_walks WHERE host_user_id = $1`,
    [userId],
  );
  if ((existing[0]?.n ?? 0) >= MAX_ROUTINES_PER_USER) {
    throw new BadRequestError("too_many_routines");
  }

  const rows = await db.query<BuddyRecurringWalk>(
    `INSERT INTO buddy_recurring_walks
       (host_user_id, mode, goal_value, activity_type, invite_user_ids,
        days_of_week, minutes_of_day, timezone)
     VALUES ($1, $2, $3, $4, $5::text[], $6::int[], $7, $8)
     RETURNING id, host_user_id, mode, goal_value, activity_type,
               invite_user_ids, days_of_week, minutes_of_day, timezone,
               is_active, NULL AS last_spawned_date`,
    [
      userId,
      input.mode,
      goalValue,
      input.activityType,
      // Stored as asserted. Re-validated at SPAWN time instead of here, because
      // a routine outlives the friendship that created it.
      Array.from(new Set(input.inviteUserIds ?? [])).filter(
        (id) => id !== userId,
      ),
      days,
      minutes,
      timezone,
    ],
  );
  return rows[0];
}

export async function updateRecurringWalk(
  userId: string,
  id: string,
  patch: Partial<RecurringWalkInput> & { isActive?: boolean },
): Promise<BuddyRecurringWalk> {
  const owned = await db.query<{ mode: string; goal_value: number | null }>(
    `SELECT mode, goal_value FROM buddy_recurring_walks
      WHERE id = $1 AND host_user_id = $2`,
    [id, userId],
  );
  if (owned.length === 0) throw new BadRequestError("routine_not_found");

  const mode = (patch.mode ?? owned[0].mode) as BuddyMode;
  // Same follows-the-mode rule as the session PATCH: an unchanged mode keeps
  // its goal, a CHANGED one demands a fresh number rather than inheriting one
  // in the wrong unit.
  const rawGoal =
    patch.goalValue !== undefined
      ? patch.goalValue
      : patch.mode !== undefined && patch.mode !== owned[0].mode
        ? null
        : owned[0].goal_value;
  const goalValue = validateGoal(
    mode,
    rawGoal === null ? null : Number(rawGoal),
  );

  const rows = await db.query<BuddyRecurringWalk>(
    `UPDATE buddy_recurring_walks
        SET mode = $3,
            goal_value = $4,
            activity_type = COALESCE($5, activity_type),
            invite_user_ids = COALESCE($6::text[], invite_user_ids),
            days_of_week = COALESCE($7::int[], days_of_week),
            minutes_of_day = COALESCE($8, minutes_of_day),
            timezone = COALESCE($9, timezone),
            is_active = COALESCE($10, is_active),
            updated_at = NOW()
      WHERE id = $1 AND host_user_id = $2
      RETURNING id, host_user_id, mode, goal_value, activity_type,
                invite_user_ids, days_of_week, minutes_of_day, timezone,
                is_active, to_char(last_spawned_date, 'YYYY-MM-DD') AS last_spawned_date`,
    [
      id,
      userId,
      mode,
      goalValue,
      patch.activityType ?? null,
      patch.inviteUserIds === undefined
        ? null
        : Array.from(new Set(patch.inviteUserIds)).filter((x) => x !== userId),
      patch.daysOfWeek === undefined ? null : normalizeDays(patch.daysOfWeek),
      patch.minutesOfDay === undefined
        ? null
        : normalizeMinutes(patch.minutesOfDay),
      patch.timezone === undefined ? null : assertValidTimezone(patch.timezone),
      patch.isActive === undefined ? null : patch.isActive,
    ],
  );
  if (rows.length === 0) throw new BadRequestError("routine_not_found");
  return rows[0];
}

export async function deleteRecurringWalk(
  userId: string,
  id: string,
): Promise<void> {
  const rows = await db.query<{ id: string }>(
    `DELETE FROM buddy_recurring_walks
      WHERE id = $1 AND host_user_id = $2 RETURNING id`,
    [id, userId],
  );
  if (rows.length === 0) throw new BadRequestError("routine_not_found");
}

/**
 * Cron: turn every routine that's due into a real scheduled session.
 *
 * Claim-and-select in ONE statement, the same shape `notifyGhostsBeaten` uses:
 * `last_spawned_date` is stamped by the very UPDATE that decides what to spawn,
 * so overlapping containers during a deploy cannot create the same walk twice.
 * Claiming BEFORE creating is deliberate — a missed occurrence is a
 * disappointment, a duplicate one is two lobbies and two sets of pushes.
 *
 * The window is `[start - 15min, start + 10min)` in the host's LOCAL time, and
 * the day match is against their local day-of-week. A cron outage inside that
 * window still lands the walk (late, promoted immediately); one longer than it
 * skips the day rather than firing a stale walk hours later.
 *
 * Never throws: one bad routine must not abort the sweep for everyone else.
 */
export async function spawnDueRecurringWalks(): Promise<number> {
  let spawned = 0;
  let due: Array<{
    id: string;
    host_user_id: string;
    mode: string;
    goal_value: number | null;
    activity_type: string;
    invite_user_ids: string[];
    scheduled_start_at: string;
  }> = [];

  try {
    due = await db.query(
      `WITH local AS (
         SELECT r.*,
                (NOW() AT TIME ZONE r.timezone) AS local_now,
                (NOW() AT TIME ZONE r.timezone)::date AS local_date,
                EXTRACT(DOW FROM (NOW() AT TIME ZONE r.timezone))::int AS local_dow,
                (EXTRACT(HOUR FROM (NOW() AT TIME ZONE r.timezone))::int * 60
                 + EXTRACT(MINUTE FROM (NOW() AT TIME ZONE r.timezone))::int
                ) AS local_minutes
           FROM buddy_recurring_walks r
          WHERE r.is_active
       )
       UPDATE buddy_recurring_walks w
          SET last_spawned_date = l.local_date, updated_at = NOW()
         FROM local l
        WHERE w.id = l.id
          AND l.local_dow = ANY(l.days_of_week)
          AND l.local_minutes >= GREATEST(0, l.minutes_of_day - $1)
          AND l.local_minutes < l.minutes_of_day + $2
          -- The claim. IS DISTINCT FROM so a NULL (never spawned) qualifies.
          AND w.last_spawned_date IS DISTINCT FROM l.local_date
       RETURNING w.id, w.host_user_id, w.mode, w.goal_value, w.activity_type,
                 w.invite_user_ids,
                 ((l.local_date + make_interval(mins => w.minutes_of_day))
                    AT TIME ZONE w.timezone)::text AS scheduled_start_at`,
      [SPAWN_LEAD_MINUTES, SPAWN_GRACE_MINUTES],
    );
  } catch (err) {
    void logError("buddy", "failed to claim due recurring walks", {
      context: { error: String(err) },
    });
    return 0;
  }

  for (const row of due) {
    try {
      // createSession re-validates every invitee (friendship, blocks,
      // enrollment, opt-out) — which is the point of storing ids rather than a
      // resolved list. A routine outlives the friendships that created it.
      await createSession(row.host_user_id, {
        mode: row.mode as BuddyMode,
        goalValue: row.goal_value,
        activityType: row.activity_type as BuddyActivityType,
        inviteUserIds: row.invite_user_ids,
        origin: "invite",
        scheduledStartAt: row.scheduled_start_at,
      });
      spawned++;
    } catch (err) {
      // Already claimed, so this occurrence is skipped rather than retried in a
      // loop. Logged loudly because a routine that stops firing is invisible.
      void logError("buddy", "failed to spawn recurring buddy walk", {
        userId: row.host_user_id,
        context: { routineId: row.id, error: String(err) },
      });
    }
  }
  return spawned;
}
