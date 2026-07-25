/**
 * Domain types for Buddy Walks & Runs.
 *
 * Wire shapes are snake_case because every buddy query is raw SQL (the service
 * reads rows straight out of `PostgresService.query`), and the iOS client
 * decodes these verbatim.
 */

/** How the group is scored. */
export type BuddyMode =
  /** No goal. Shared presence + live stats + one collab post. The zero-config default. */
  | "together"
  /** Everyone's distance pools toward one shared target. Nobody loses. */
  | "coop_goal"
  /** First participant to reach `goal_value` miles wins. */
  | "race_goal"
  /** Everyone moves for `goal_value` minutes; the most distance wins. */
  | "race_time";

export type BuddySessionStatus = "lobby" | "active" | "completed" | "cancelled";

/** Which door the group came through. Measured so we know what to invest in. */
export type BuddyOrigin = "invite" | "code" | "join_active" | "nearby";

export type BuddyParticipantStatus =
  | "invited"
  | "joined"
  | "ready"
  | "active"
  | "finished"
  | "left"
  | "declined";

export const BUDDY_MODES: BuddyMode[] = [
  "together",
  "coop_goal",
  "race_goal",
  "race_time",
];

export const BUDDY_ACTIVITY_TYPES = ["running", "walking", "any"] as const;
export type BuddyActivityType = (typeof BUDDY_ACTIVITY_TYPES)[number];

/**
 * Hard cap on participants.
 *
 * Load-bearing, not cosmetic: every active participant POSTs progress every 5s,
 * so an 8-person session is ~96 writes/min against a pool with max 20
 * connections. Raising this raises sustained write load linearly.
 */
export const BUDDY_MAX_PARTICIPANTS = 8;

/**
 * Seconds between `POST /start` and the session's actual `started_at`.
 *
 * The countdown target is set in the FUTURE and handed to every client, so all
 * participants count down to the same wall-clock instant instead of each
 * starting whenever its own request happened to return.
 */
export const BUDDY_START_COUNTDOWN_SECONDS = 8;

/**
 * A participant whose last progress report is older than this reads as "out of
 * range" in the roster. Derived at read time — no cron involved.
 */
export const BUDDY_STALE_PROGRESS_SECONDS = 90;

/**
 * Sessions abandoned this long are auto-completed by the hourly cron. Long
 * enough to cover a slow marathon-pace walk plus a phone dying mid-session.
 */
export const BUDDY_ABANDON_HOURS = 6;

/**
 * Upper bound on believable speed, in meters/second, used to clamp live
 * progress. Mirrors `maxPlausibleSpeed` in the iOS WorkoutLocationManager so
 * client and server agree on what a teleport looks like.
 */
export const BUDDY_MAX_SPEED_MPS = 12;

export const METERS_PER_MILE = 1609.344;

export interface BuddySessionRow {
  id: string;
  join_code: string;
  host_user_id: string | null;
  mode: BuddyMode;
  goal_value: number | null;
  activity_type: string;
  status: BuddySessionStatus;
  origin: BuddyOrigin;
  scheduled_start_at: string | null;
  started_at: string | null;
  ends_at: string | null;
  ended_at: string | null;
  winner_user_id: string | null;
  state_version: number;
  local_date: string;
  created_at: string;
}

export interface BuddyParticipantRow {
  session_id: string;
  user_id: string;
  status: BuddyParticipantStatus;
  invited_by: string | null;
  joined_at: string | null;
  ready_at: string | null;
  finished_at: string | null;
  distance_miles: number;
  duration_seconds: number;
  last_progress_at: string | null;
  workout_id: string | null;
  final_distance_miles: number | null;
  place: number | null;
}

/** A participant as returned to clients — row plus joined profile + derived flags. */
export interface BuddyParticipantView {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  status: BuddyParticipantStatus;
  distance_miles: number;
  duration_seconds: number;
  /** True when last_progress_at is older than BUDDY_STALE_PROGRESS_SECONDS. */
  is_stale: boolean;
  is_host: boolean;
  place: number | null;
  final_distance_miles: number | null;
}

/** The full snapshot returned by GET /state and by POST /progress. */
export interface BuddySessionState {
  id: string;
  join_code: string;
  mode: BuddyMode;
  goal_value: number | null;
  activity_type: string;
  status: BuddySessionStatus;
  host_user_id: string | null;
  started_at: string | null;
  ends_at: string | null;
  ended_at: string | null;
  winner_user_id: string | null;
  state_version: number;
  participants: BuddyParticipantView[];
  /** Pooled distance across all participants. Only meaningful for coop_goal. */
  group_distance_miles: number;
}

export type BuddyEventKind =
  | "created"
  | "joined"
  | "left"
  | "declined"
  | "started"
  | "goal_hit"
  | "finished"
  | "completed";
