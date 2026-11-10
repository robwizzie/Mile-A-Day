import { PostgresService } from "./DbService.js";
import { countedWorkoutSql } from "./mileTime.js";
import {
  DAILY_GOAL_TOLERANCE,
  deviceMeasuredDistanceSql,
  deviceMeasuredWorkoutSql,
} from "./workoutService.js";
import { userOffsetMinutesSql } from "./dailyResetTime.js";

const db = PostgresService.getInstance();

/**
 * One-day events (Champ 5K Day). Code constants, like the holidays: an event
 * is a local DATE, a distance to cover that day (every counted,
 * device-measured walk and run adds up, in each person's own time zone), and
 * a medal that unlocks its Flamey items. The medal is seeded in
 * badgeService's EXTRA_BADGES (category `competition`, so it is never
 * revoked) and granted at sync by `eventHitsForWorkouts`.
 */
export interface SpecialEvent {
  id: string;
  title: string;
  /** The local day, YYYY-MM-DD. */
  date: string;
  /** Distance to cover that day. */
  miles: number;
  badgeId: string;
  /** Flamey items the medal unlocks (their skins' `unlock.badge`). */
  rewardItemIds: string[];
  /** Days before the event it shows in the app. */
  previewDays: number;
  /** Days after it keeps showing (the result). */
  afterDays: number;
}

export const SPECIAL_EVENTS: SpecialEvent[] = [
  {
    id: "champ_5k_2026",
    title: "Champ 5K Day",
    date: "2026-11-14",
    miles: 3.1,
    badgeId: "event_champ_5k_2026",
    rewardItemIds: ["champ_shorts", "boxing_gloves"],
    previewDays: 14,
    afterDays: 3,
  },
];

/** The miles that count as done: the distance with the daily-goal leeway. */
export function eventTargetMiles(e: SpecialEvent): number {
  return e.miles * DAILY_GOAL_TOLERANCE;
}

/** One person's device-measured, counted miles per local day, for `$2` dates. */
function eventDaysSql(): string {
  return `
    SELECT w.user_id, to_char(w.local_date, 'YYYY-MM-DD') AS local_date,
           SUM(${deviceMeasuredDistanceSql("w")})::double precision AS miles,
           (ARRAY_AGG(w.workout_id ORDER BY w.device_end_date DESC))[1] AS workout_id,
           MAX(w.device_end_date) AS earned_at
      FROM workouts w
     WHERE w.user_id = ANY($1::text[])
       AND w.local_date = ANY($2::date[])
       AND ${countedWorkoutSql("w")}
       AND ${deviceMeasuredWorkoutSql("w")}
     GROUP BY w.user_id, w.local_date`;
}

export type EventHit = {
  badgeId: string;
  workoutId: string;
  earnedAt: Date | string;
};

async function hitsOn(
  userId: string,
  events: SpecialEvent[],
): Promise<EventHit[]> {
  if (events.length === 0) return [];
  const rows = await db.query<{
    local_date: string;
    miles: number;
    workout_id: string;
    earned_at: Date | string;
  }>(eventDaysSql(), [[userId], events.map((e) => e.date)]);
  const out: EventHit[] = [];
  for (const e of events) {
    const day = rows.find((r) => r.local_date === e.date);
    if (day && Number(day.miles) >= eventTargetMiles(e)) {
      out.push({
        badgeId: e.badgeId,
        workoutId: day.workout_id,
        earnedAt: day.earned_at,
      });
    }
  }
  return out;
}

/**
 * Events this upload may have completed: only events whose day one of the
 * uploaded workouts belongs to, then the whole day is summed. The newest
 * workout of that day is the medal's trigger (and its date).
 */
export async function eventHitsForWorkouts(
  userId: string,
  workoutIds: string[],
): Promise<EventHit[]> {
  if (workoutIds.length === 0) return [];
  const dates = SPECIAL_EVENTS.map((e) => e.date);
  const touched = await db.query<{ local_date: string }>(
    `SELECT DISTINCT to_char(local_date, 'YYYY-MM-DD') AS local_date
       FROM workouts
      WHERE user_id = $1 AND workout_id = ANY($2::text[]) AND local_date = ANY($3::date[])`,
    [userId, workoutIds, dates],
  );
  const days = new Set(touched.map((t) => t.local_date));
  return hitsOn(
    userId,
    SPECIAL_EVENTS.filter((e) => days.has(e.date)),
  );
}

/** Every event the user's history completes (Recalibrate, the retro sweep). */
export async function eventHitsAllHistory(userId: string): Promise<EventHit[]> {
  return hitsOn(userId, SPECIAL_EVENTS);
}

function addDays(day: string, n: number): string {
  return new Date(Date.parse(`${day}T00:00:00Z`) + n * 86_400_000)
    .toISOString()
    .slice(0, 10);
}

/** Whole days from `from` to `to` (YYYY-MM-DD). */
function daysBetween(from: string, to: string): number {
  return Math.round(
    (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) /
      86_400_000,
  );
}

/** The events showing for a user on their local `today`. */
export function eventsShowingOn(today: string): SpecialEvent[] {
  return SPECIAL_EVENTS.filter(
    (e) =>
      today >= addDays(e.date, -e.previewDays) &&
      today <= addDays(e.date, e.afterDays),
  );
}

export interface SpecialEventView {
  event_id: string;
  title: string;
  date: string;
  miles: number;
  /** The distance that counts as done (the daily-goal leeway). */
  target_miles: number;
  badge_id: string;
  reward_item_ids: string[];
  state: "upcoming" | "today" | "over";
  days_until: number;
  my_miles: number;
  earned: boolean;
  /** Friends with any miles on the day, and friends who finished. */
  friends_going: number;
  friends_done: number;
  /** Up to three of those friends (finishers first), for the avatar row. */
  friends_preview: Array<{
    user_id: string;
    username: string | null;
    profile_image_url: string | null;
  }>;
}

/** Events showing for this user, with their own numbers and their friends'. */
export async function getSpecialEventsForUser(
  userId: string,
  /** Tests only: judge as if the user's local day were this. */
  opts: { today?: string } = {},
): Promise<{ events: SpecialEventView[] }> {
  const today =
    opts.today ??
    (
      await db.query<{ today: string }>(
        `SELECT to_char((NOW() + (${userOffsetMinutesSql("$1")} || ' minutes')::interval)::date, 'YYYY-MM-DD') AS today`,
        [userId],
      )
    )[0].today;
  const showing = eventsShowingOn(today);
  if (showing.length === 0) return { events: [] };

  const friends = await db.query<{ friend_id: string }>(
    `SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted'`,
    [userId],
  );
  const people = [userId, ...friends.map((f) => f.friend_id)];
  const days = await db.query<{
    user_id: string;
    local_date: string;
    miles: number;
  }>(eventDaysSql(), [people, showing.map((e) => e.date)]);
  const earnedRows = await db.query<{ badge_id: string }>(
    `SELECT badge_id FROM user_badges WHERE user_id = $1 AND badge_id = ANY($2::text[])`,
    [userId, showing.map((e) => e.badgeId)],
  );
  const earned = new Set(earnedRows.map((r) => r.badge_id));

  const events: SpecialEventView[] = [];
  for (const e of showing) {
    const target = eventTargetMiles(e);
    const onDay = days.filter((d) => d.local_date === e.date);
    const mine = Number(onDay.find((d) => d.user_id === userId)?.miles ?? 0);
    const theirs = onDay
      .filter((d) => d.user_id !== userId && Number(d.miles) > 0)
      .sort((a, b) => Number(b.miles) - Number(a.miles));
    const previewIds = theirs.slice(0, 3).map((d) => d.user_id);
    const preview = previewIds.length
      ? await db.query<{
          user_id: string;
          username: string | null;
          profile_image_url: string | null;
        }>(
          `SELECT user_id, username, profile_image_url FROM users WHERE user_id = ANY($1::text[])`,
          [previewIds],
        )
      : [];
    const d = daysBetween(today, e.date);
    events.push({
      event_id: e.id,
      title: e.title,
      date: e.date,
      miles: e.miles,
      target_miles: Math.round(target * 100) / 100,
      badge_id: e.badgeId,
      reward_item_ids: e.rewardItemIds,
      state: d > 0 ? "upcoming" : d === 0 ? "today" : "over",
      days_until: Math.max(0, d),
      my_miles: Math.round(mine * 100) / 100,
      earned: earned.has(e.badgeId),
      friends_going: theirs.length,
      friends_done: theirs.filter((t) => Number(t.miles) >= target).length,
      friends_preview: previewIds
        .map((id) => preview.find((p) => p.user_id === id))
        .filter((p): p is NonNullable<typeof p> => !!p),
    });
  }
  return { events };
}

/** Claims one push per event, person and kind; false = already sent. */
export async function claimEventPush(
  eventId: string,
  userId: string,
  kind: string,
): Promise<boolean> {
  const rows = await db.query(
    `INSERT INTO special_event_push_log (event_id, user_id, kind) VALUES ($1, $2, $3)
     ON CONFLICT (event_id, user_id, kind) DO NOTHING RETURNING user_id`,
    [eventId, userId, kind],
  );
  return rows.length > 0;
}

/** The day's miles for a set of people on an event's date. */
export async function milesOnEventDay(
  e: SpecialEvent,
  userIds: string[],
): Promise<Map<string, number>> {
  if (userIds.length === 0) return new Map();
  const rows = await db.query<{ user_id: string; miles: number }>(
    eventDaysSql(),
    [userIds, [e.date]],
  );
  return new Map(rows.map((r) => [r.user_id, Number(r.miles)]));
}
