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

/**
 * Whitelist for the create endpoint.
 *
 * `origin` is the only enum on the create payload that reached the DB
 * unvalidated, so a typo from a client surfaced as a 500 off the table's CHECK
 * constraint rather than a 400. Mirrors BUDDY_MODES / BUDDY_ACTIVITY_TYPES.
 */
export const BUDDY_ORIGINS: BuddyOrigin[] = [
  "invite",
  "code",
  "join_active",
  "nearby",
];

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
  /// The real HKWorkout, stamped by reconcileBuddySessions once it syncs. Null
  /// until then — the client uses it to link a recap post to the run.
  workout_id: string | null;
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
  /** Set for a walk booked ahead of time; the lobby counts down to it. */
  scheduled_start_at: string | null;
  started_at: string | null;
  ends_at: string | null;
  ended_at: string | null;
  winner_user_id: string | null;
  state_version: number;
  participants: BuddyParticipantView[];
  /** Pooled distance across all participants. Only meaningful for coop_goal. */
  group_distance_miles: number;
}

// ─── History ────────────────────────────────────────────────────────────
//
// The archive of walks you've already taken. Everything here is DERIVED from
// the same participant rows the live session wrote — no new writes, no counters
// to drift, and a walk taken before this screen existed shows up in it.

/** One person on a past walk, as the history screen draws them. */
export interface BuddyHistoryParticipant {
  user_id: string;
  /**
   * Null when the viewer can no longer see this person's profile (the
   * friendship ended). The walk still happened and their miles still count
   * toward the group total — but "we walked together once" is not permanent
   * access to someone's name and photo, so the client renders them anonymously.
   */
  username: string | null;
  first_name: string | null;
  profile_image_url: string | null;
  /** Reconciled distance where it exists, live distance otherwise. */
  distance_miles: number;
  duration_seconds: number;
  place: number | null;
  is_host: boolean;
}

/** A photo from a past walk. Media urls are signed by the controller. */
export interface BuddyHistoryPhoto {
  post_id: string;
  user_id: string;
  media_url: string;
  caption: string | null;
  photo_locked?: boolean;
}

/** One finished buddy walk, newest first on the history screen. */
export interface BuddyHistoryEntry {
  id: string;
  mode: BuddyMode;
  activity_type: string;
  goal_value: number | null;
  local_date: string;
  started_at: string | null;
  ended_at: string | null;
  winner_user_id: string | null;
  /** Pooled distance across everyone who finished — including anyone the
   * viewer can't see, so the number matches what the recap showed on the day. */
  group_distance_miles: number;
  my_distance_miles: number;
  my_duration_seconds: number;
  my_place: number | null;
  participants: BuddyHistoryParticipant[];
  photos: BuddyHistoryPhoto[];
  /** Keyset cursor for the next page. */
  cursor: string;
}

/** Lifetime shared-walk totals, shown as the history screen's headline. */
export interface BuddyHistoryTotals {
  walks: number;
  /** The VIEWER's own miles across those walks — see getBuddyPartners for why
   * a pooled figure would disagree with itself from the other side. */
  miles: number;
  /** Distinct people you've finished a walk with. */
  partners: number;
  first_walk_date: string | null;
  last_walk_date: string | null;
}

export type BuddyEventKind =
  | "created"
  /** Host changed the lobby's mode/goal/activity/schedule before starting. */
  | "updated"
  | "joined"
  | "left"
  | "declined"
  | "started"
  | "goal_hit"
  | "finished"
  | "completed";
