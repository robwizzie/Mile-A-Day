import { PostgresService } from "./DbService.js";
import { areFriends } from "./friendshipService.js";
import { JOINABLE_WINDOW_SQL, OCCUPYING_STATUSES_SQL } from "./buddyFeatures.js";
import type { BuddyJoinRequestView } from "../types/buddy.js";
import { sendPush } from "./pushNotificationService.js";
import {
  allowedRecipients,
  shouldSendNotification,
} from "./notificationSettingsService.js";
import { CLIENT_FEATURES, userSupports } from "./clientFeatures.js";
import { evaluateSocialBadgesForUser } from "./badgeService.js";
import { logError } from "./errorLogService.js";
import { BadRequestError } from "../errors/Errors.js";
import {
  BUDDY_ABANDON_HOURS,
  BUDDY_MAX_PARTICIPANTS,
  BUDDY_MAX_SPEED_MPS,
  BUDDY_START_COUNTDOWN_SECONDS,
  BUDDY_STALE_PROGRESS_SECONDS,
  METERS_PER_MILE,
  type BuddyActivityType,
  type BuddyEventKind,
  type BuddyHistoryEntry,
  type BuddyHistoryParticipant,
  type BuddyHistoryTotals,
  type BuddyLocationType,
  type BuddyMode,
  type BuddyOrigin,
  type BuddyParticipantView,
  type BuddySessionRow,
  type BuddySessionState,
} from "../types/buddy.js";
import {
  buddySessionPhotos,
  buddySessionPost,
  type BuddySessionPost,
  buddySessionPostIds,
} from "./postService.js";

const db = PostgresService.getInstance();

/**
 * Buddy Walks & Runs — live shared walk/run sessions.
 *
 * SERVER-AUTHORITATIVE BY DESIGN. Every participant reports progress here and
 * reads everyone else back from here; there is no peer-to-peer link. That is
 * what makes a remote session work at all, and what keeps a co-located session
 * alive when two people drift apart mid-run (which happens the moment one
 * person walks faster than the other).
 *
 * A session DECORATES a normal workout. Participants run the ordinary
 * tracking → HealthKit → POST /workouts/:id/upload path, so streaks,
 * daily-mile, competitions and badges are untouched. The `distance_miles` on a
 * participant row is DISPLAY state; the authoritative number is stamped later
 * by reconcileBuddySessions() from the real synced HKWorkout.
 */

// ─── Blocks ─────────────────────────────────────────────────────────────
//
// Blocks are always bidirectional. Copied from the canonical predicate used by
// postService/feed queries — a one-directional check here would let a blocked
// user pull their blocker into a session.
const NOT_BLOCKED_SQL = `NOT EXISTS (
  SELECT 1 FROM user_blocks b
  WHERE (b.blocker_id = $1 AND b.blocked_id = $2)
     OR (b.blocker_id = $2 AND b.blocked_id = $1)
)`;

async function isBlockedEitherWay(a: string, b: string): Promise<boolean> {
  const rows = await db.query(`SELECT 1 WHERE ${NOT_BLOCKED_SQL} IS NOT TRUE`, [
    a,
    b,
  ]);
  return rows.length > 0;
}

// ─── Join codes ─────────────────────────────────────────────────────────

// Deliberately excludes 0/O/1/I/L — these get read aloud across a room, and a
// code that can't be transcribed is worse than no code at all.
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

function randomJoinCode(): string {
  let out = "";
  for (let i = 0; i < 6; i++) {
    out += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return out;
}

// ─── Events ─────────────────────────────────────────────────────────────

async function recordEvent(
  sessionId: string,
  userId: string | null,
  kind: BuddyEventKind,
  payload: Record<string, unknown> = {},
): Promise<void> {
  await db.query(
    `INSERT INTO buddy_session_events (session_id, user_id, kind, payload)
     VALUES ($1, $2, $3, $4::jsonb)`,
    [sessionId, userId, kind, JSON.stringify(payload)],
  );
}

/**
 * Bump the polling cursor. Every mutation must call this (or include the bump
 * in its own UPDATE) or clients will sit on a 304 and never see the change.
 */
async function bumpVersion(sessionId: string): Promise<void> {
  await db.query(
    `UPDATE buddy_sessions SET state_version = state_version + 1 WHERE id = $1`,
    [sessionId],
  );
}

// ─── Reads ──────────────────────────────────────────────────────────────

async function getSessionRow(
  sessionId: string,
): Promise<BuddySessionRow | null> {
  const rows = await db.query<BuddySessionRow>(
    `SELECT id, join_code, host_user_id, mode, goal_value, activity_type, status,
            origin, scheduled_start_at, started_at, ends_at, ended_at,
            winner_user_id, state_version, local_date, created_at
       FROM buddy_sessions WHERE id = $1`,
    [sessionId],
  );
  return rows[0] ?? null;
}

/** Membership check. Only participants may read a session's state. */
async function participantStatus(
  sessionId: string,
  userId: string,
): Promise<string | null> {
  const rows = await db.query<{ status: string }>(
    `SELECT status FROM buddy_session_participants
      WHERE session_id = $1 AND user_id = $2`,
    [sessionId, userId],
  );
  return rows[0]?.status ?? null;
}

async function loadParticipants(
  sessionId: string,
  hostUserId: string | null,
): Promise<BuddyParticipantView[]> {
  const rows = await db.query<{
    user_id: string;
    username: string | null;
    first_name: string | null;
    last_name: string | null;
    profile_image_url: string | null;
    status: BuddyParticipantView["status"];
    distance_miles: number;
    duration_seconds: number;
    is_stale: boolean;
    place: number | null;
    final_distance_miles: number | null;
    workout_id: string | null;
    location_type: BuddyLocationType | null;
    is_paused: boolean;
  }>(
    // Staleness means "was reporting, then stopped" — NOT "hasn't reported
    // yet". A participant's first progress report is up to 5s out, so falling
    // back to the session start keeps the whole roster from rendering as
    // out-of-range for the first moments of every walk.
    `SELECT p.user_id, u.username, u.first_name, u.last_name, u.profile_image_url,
            p.status, p.distance_miles, p.duration_seconds, p.place,
            p.final_distance_miles, p.workout_id, p.location_type,
            (p.status = 'active'
             AND COALESCE(p.last_progress_at, s.started_at, NOW())
                   < NOW() - ($2 || ' seconds')::interval
            ) AS is_stale,
            -- Only a walker still ON the walk can be paused: a finished row
            -- keeps whatever flag its last report carried, and rendering that
            -- would put a pause badge on someone who is done.
            (p.status = 'active' AND COALESCE(p.is_paused, false)) AS is_paused
       FROM buddy_session_participants p
       JOIN users u ON u.user_id = p.user_id
       JOIN buddy_sessions s ON s.id = p.session_id
      WHERE p.session_id = $1
        -- Someone waiting at the door is not on the roster. Load-bearing for
        -- shipped clients: they decode this array's status as a closed enum,
        -- and one unknown value fails the WHOLE snapshot. Requests ride the
        -- additive join_requests field instead (loadJoinRequests).
        AND p.status <> 'requested'
      ORDER BY p.distance_miles DESC, p.joined_at ASC NULLS LAST`,
    [sessionId, String(BUDDY_STALE_PROGRESS_SECONDS)],
  );

  return rows.map((r) => ({
    user_id: r.user_id,
    username: r.username,
    first_name: r.first_name,
    last_name: r.last_name,
    profile_image_url: r.profile_image_url,
    status: r.status,
    distance_miles: Number(r.distance_miles) || 0,
    duration_seconds: Number(r.duration_seconds) || 0,
    is_stale: r.is_stale === true,
    is_paused: r.is_paused === true,
    is_host: r.user_id === hostUserId,
    place: r.place,
    final_distance_miles:
      r.final_distance_miles === null ? null : Number(r.final_distance_miles),
    workout_id: r.workout_id,
    location_type: r.location_type,
  }));
}

/**
 * People asking to be let in, with the members each of them is friends with.
 *
 * `friend_user_ids` is what makes the request answerable by more than the
 * host: any member on that list vouches for them. It's the requester's OWN
 * friendship rows, either direction, against the people who are actually in
 * the walk — never against invitees who haven't answered.
 */
async function loadJoinRequests(
  sessionId: string,
): Promise<BuddyJoinRequestView[]> {
  return db.query<BuddyJoinRequestView>(
    `SELECT r.user_id, u.username, u.first_name, u.last_name,
            u.profile_image_url,
            to_char(r.requested_at AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS requested_at,
            ARRAY(
              SELECT m.user_id
                FROM buddy_session_participants m
               WHERE m.session_id = r.session_id
                 AND m.status IN ('joined', 'ready', 'active', 'finished')
                 AND EXISTS (
                   SELECT 1 FROM friendships f
                    WHERE f.status = 'accepted'
                      AND ((f.user_id = r.user_id AND f.friend_id = m.user_id)
                        OR (f.user_id = m.user_id AND f.friend_id = r.user_id)))
               ORDER BY m.joined_at ASC NULLS LAST
            )::text[] AS friend_user_ids
       FROM buddy_session_participants r
       JOIN users u ON u.user_id = r.user_id
      WHERE r.session_id = $1 AND r.status = 'requested'
      ORDER BY r.requested_at ASC NULLS LAST`,
    [sessionId],
  );
}

/** The snapshot every mutation returns: row + roster + the queue at the door. */
async function buildState(session: BuddySessionRow): Promise<BuddySessionState> {
  const [participants, joinRequests] = await Promise.all([
    loadParticipants(session.id, session.host_user_id),
    loadJoinRequests(session.id),
  ]);
  return toState(session, participants, joinRequests);
}

function toState(
  session: BuddySessionRow,
  participants: BuddyParticipantView[],
  joinRequests: BuddyJoinRequestView[] = [],
): BuddySessionState {
  // Only participants who actually got moving count toward the pooled total —
  // an invitee who never joined must not dilute a co-op goal.
  const groupDistance = participants
    .filter((p) => p.status === "active" || p.status === "finished")
    .reduce((sum, p) => sum + p.distance_miles, 0);

  return {
    id: session.id,
    join_code: session.join_code,
    mode: session.mode,
    goal_value: session.goal_value === null ? null : Number(session.goal_value),
    activity_type: session.activity_type,
    status: session.status,
    host_user_id: session.host_user_id,
    scheduled_start_at: session.scheduled_start_at,
    started_at: session.started_at,
    ends_at: session.ends_at,
    ended_at: session.ended_at,
    winner_user_id: session.winner_user_id,
    state_version: session.state_version,
    participants,
    group_distance_miles: Math.round(groupDistance * 1000) / 1000,
    join_requests: joinRequests,
  };
}

/**
 * The polling contract.
 *
 * Returns null when the caller's `since` cursor already matches the stored
 * version, which the controller turns into a 304. finalizeIfDue runs first so
 * a race_time session ends on time without needing a minute-granularity cron —
 * the same "recompute on read" shape competitions already use for standings.
 */
export async function getSessionState(
  sessionId: string,
  userId: string,
  since?: number,
): Promise<BuddySessionState | null> {
  const membership = await participantStatus(sessionId, userId);
  if (membership === null) {
    throw new BadRequestError("not_a_participant");
  }

  // A scheduled session starts on time for whoever is looking, without
  // waiting for the cron tick — same lazy shape as finalizeIfDue below.
  await promoteScheduledIfDue(sessionId);
  await finalizeIfDue(sessionId);

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");

  if (
    since !== undefined &&
    Number.isFinite(since) &&
    session.state_version <= since
  ) {
    return null;
  }

  return buildState(session);
}

// ─── Create ─────────────────────────────────────────────────────────────

export interface CreateSessionInput {
  mode: BuddyMode;
  goalValue?: number | null;
  activityType: BuddyActivityType;
  inviteUserIds?: string[];
  origin?: BuddyOrigin;
  /**
   * ISO timestamp for a scheduled walk. The session sits in `lobby` with
   * `started_at` NULL until this moment, then is promoted exactly like a manual
   * start. Null/absent = start whenever the host says.
   */
  scheduledStartAt?: string | null;
}

/**
 * A goal is required for every mode except 'together', which is goal-less by
 * definition, and the ceiling depends on the unit (minutes vs miles).
 *
 * Lives here rather than inline in createSession because the lobby can now
 * change the mode after the fact: switching 'together' → 'race_goal' has to
 * demand a goal on the way through, and switching back has to drop it. Two
 * copies of that rule would let the lobby write a state create would reject.
 */
export function validateGoal(
  mode: BuddyMode,
  raw: number | null,
): number | null {
  if (mode === "together") return null;
  if (raw === null || !(raw > 0)) throw new BadRequestError("goal_required");
  if (mode === "race_time" && raw > 24 * 60) {
    throw new BadRequestError("goal_too_large");
  }
  if ((mode === "coop_goal" || mode === "race_goal") && raw > 200) {
    throw new BadRequestError("goal_too_large");
  }
  return raw;
}

/**
 * The host's UTC offset in minutes — their notification settings' offset,
 * else the offset stamped on their latest workout, else Eastern. The same
 * resolution liveTrackingService uses for a friend's local date.
 */
async function hostUtcOffsetMinutes(hostUserId: string): Promise<number> {
  const rows = await db.query<{ offset: number | null }>(
    `SELECT COALESCE(
              (SELECT ns.timezone_offset_minutes FROM notification_settings ns
                WHERE ns.user_id = $1::text),
              (SELECT w.timezone_offset FROM workouts w
                WHERE w.user_id = $1::varchar
                ORDER BY w.device_end_date DESC LIMIT 1)
            )::int AS offset`,
    [hostUserId],
  );
  const offset = rows[0]?.offset;
  return offset === null || offset === undefined ? -240 : Number(offset);
}

/**
 * `local_date` for a session: the calendar day of the instant it happens
 * (the scheduled start, else now) in the HOST's timezone. It used to be the
 * CREATION instant in New York, which filed a 9:30 PM Pacific walk under
 * tomorrow, an Australian morning under yesterday, and every scheduled walk
 * under the day it was booked — and this date drives "Today/Yesterday",
 * partner history and the earn-to-view photo gate.
 */
const SESSION_LOCAL_DATE_SQL = (whenParam: string, offsetParam: string) =>
  `(((COALESCE(${whenParam}::timestamptz, NOW()) AT TIME ZONE 'UTC')
      + (${offsetParam}::int || ' minutes')::interval)::date)`;

export async function createSession(
  hostUserId: string,
  input: CreateSessionInput,
): Promise<BuddySessionState> {
  const { mode, activityType } = input;

  const goalValue = validateGoal(mode, input.goalValue ?? null);
  const hostOffset = await hostUtcOffsetMinutes(hostUserId);

  const inviteIds = Array.from(new Set(input.inviteUserIds ?? [])).filter(
    (id) => id !== hostUserId,
  );
  if (inviteIds.length + 1 > BUDDY_MAX_PARTICIPANTS) {
    throw new BadRequestError("too_many_participants");
  }

  const eligible = await eligibleInvitees(hostUserId, inviteIds);

  // Retry on join-code collision. The unique index is partial (open sessions
  // only), so the space is tiny in practice and a handful of attempts is plenty.
  let sessionId: string | null = null;
  let joinCode = "";
  for (let attempt = 0; attempt < 5 && sessionId === null; attempt++) {
    joinCode = randomJoinCode();
    try {
      const inserted = await db.query<{ id: string }>(
        `INSERT INTO buddy_sessions
           (join_code, host_user_id, mode, goal_value, activity_type, status,
            origin, scheduled_start_at, local_date)
         VALUES ($1, $2, $3, $4, $5, 'lobby', $6, $7::timestamptz,
                 ${SESSION_LOCAL_DATE_SQL("$7", "$8")})
         RETURNING id`,
        [
          joinCode,
          hostUserId,
          mode,
          goalValue,
          activityType,
          input.origin ?? "invite",
          input.scheduledStartAt ?? null,
          String(hostOffset),
        ],
      );
      sessionId = inserted[0]?.id ?? null;
    } catch (err: any) {
      if (err?.code !== "23505") throw err;
    }
  }
  if (!sessionId) throw new BadRequestError("could_not_allocate_code");

  // Host is 'joined' immediately — they never see their own invite. Inserted
  // in the SAME statement as the invitees: one round trip for the whole roster
  // instead of one per person, which is what a host with three friends picked
  // was paying before the lobby could open.
  await db.query(
    `INSERT INTO buddy_session_participants
       (session_id, user_id, status, invited_by, joined_at)
     SELECT $1, $2, 'joined', NULL, NOW()
     UNION ALL
     SELECT $1, invitee, 'invited', $2, NULL
       FROM unnest($3::text[]) AS invitee
     ON CONFLICT (session_id, user_id) DO NOTHING`,
    [sessionId, hostUserId, eligible],
  );

  await recordEvent(sessionId, hostUserId, "created", { mode, goalValue });
  void notifyInvitees(
    sessionId,
    hostUserId,
    eligible,
    input.scheduledStartAt ?? null,
  );

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  return buildState(session);
}

/**
 * "starting now" / "in 20 minutes" / "in 3 hours" / "in 2 days" — an invite
 * to a walk booked for Thursday used to say "starting now".
 */
export function inviteWhenText(scheduledStartAt: string | null): string {
  if (!scheduledStartAt) return "starting now";
  const minutes = Math.round(
    (new Date(scheduledStartAt).getTime() - Date.now()) / 60_000,
  );
  if (minutes < 2) return "starting now";
  if (minutes < 60) return `in ${minutes} minutes`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `in ${hours} ${hours === 1 ? "hour" : "hours"}`;
  const days = Math.round(hours / 24);
  return `in ${days} ${days === 1 ? "day" : "days"}`;
}

async function displayName(userId: string): Promise<string> {
  const rows = await db.query<{
    first_name: string | null;
    username: string | null;
  }>(`SELECT first_name, username FROM users WHERE user_id = $1`, [userId]);
  return rows[0]?.first_name || rows[0]?.username || "A friend";
}

/**
 * "Sam wants to walk with you" — to each new invitee.
 *
 * `inviterId` is whoever tapped, which is no longer always the host: a member
 * can pull people in mid-walk. The push still carries `host_user_id` (the
 * session's), because that is the key shipped builds already read, and adds
 * the inviter beside it. The copy knows the phase — an invite to a walk that
 * is already underway says so, or "starting now" over a crew half a mile in
 * reads as a room that will wait for you.
 */
async function notifyInvitees(
  sessionId: string,
  hostUserId: string,
  inviteeIds: string[],
  scheduledStartAt: string | null = null,
  inviterId: string = hostUserId,
  sessionStatus: string = "lobby",
): Promise<void> {
  if (inviteeIds.length === 0) return;
  try {
    const inviterName = await displayName(inviterId);
    const body =
      sessionStatus === "active"
        ? `${inviterName} is out now and wants you on the walk — join in`
        : `${inviterName} wants to walk with you — ${inviteWhenText(scheduledStartAt)}`;

    // Two queries for the whole crew, then the pushes in parallel: an invite
    // is "starting now", and a room of eight used to wait on sixteen
    // sequential preference reads before the first one went out.
    const recipients = await allowedRecipients(inviteeIds, inviterId, "buddy");
    await Promise.all(
      recipients.map((inviteeId) =>
        sendPush(inviteeId, {
          title: "Buddy Walk",
          body,
          type: "buddy_invite",
          category: "BUDDY_INVITE",
          data: {
            session_id: sessionId,
            host_user_id: hostUserId,
            inviter_user_id: inviterId,
          },
        }),
      ),
    );
  } catch (err) {
    void logError("buddy", "failed to notify buddy invitees", {
      userId: inviterId,
      context: { sessionId, error: String(err) },
    });
  }
}

// ─── Join / decline / leave ─────────────────────────────────────────────

/**
 * Join by session id or by code.
 *
 * Serialized on an advisory lock keyed to the session so the participant cap
 * cannot be exceeded by simultaneous joins — the same primitive
 * h2hMatchupService uses for its once-per-day matchmaker. Checking the count
 * and inserting in separate statements without the lock is exactly the race
 * that lets a 9th person into an 8-person room.
 *
 * JOINING AN ALREADY-RUNNING WALK LANDS 'active', NOT 'joined'. This is the
 * whole of the "a friend joined after we started and nobody could see them"
 * bug, and it was three failures wearing one coat: every roster surface draws
 * `status IN ('active','finished')`, `toState`'s pooled total counts the same
 * set, and `recordProgress` rejects a non-active participant outright — so the
 * late arrival was invisible, contributed nothing to a co-op goal, and had
 * every one of their own progress reports 400'd for the rest of the walk. Only
 * `activateSession` ever promoted anybody, and it runs once, at start.
 */
export async function joinSession(
  userId: string,
  opts: { sessionId?: string; code?: string; locationType?: BuddyLocationType },
): Promise<BuddySessionState> {
  let sessionId = opts.sessionId ?? null;

  if (!sessionId && opts.code) {
    const rows = await db.query<{ id: string }>(
      `SELECT id FROM buddy_sessions
        WHERE join_code = $1 AND status IN ('lobby', 'active')`,
      [opts.code.trim().toUpperCase()],
    );
    sessionId = rows[0]?.id ?? null;
  }
  if (!sessionId) throw new BadRequestError("session_not_found");

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  if (session.status !== "lobby" && session.status !== "active") {
    throw new BadRequestError("session_closed");
  }

  // Joining by code still requires friendship with the host — the code is a
  // convenience, never an authorization bypass.
  if (session.host_user_id && session.host_user_id !== userId) {
    const existingRows = await db.query<{
      status: string;
      requested_at: string | null;
    }>(
      `SELECT status, requested_at FROM buddy_session_participants
        WHERE session_id = $1 AND user_id = $2`,
      [sessionId, userId],
    );
    const existing = existingRows[0] ?? null;
    // A row that came in through the request door carries no authorization
    // of its own: 'requested' is still waiting for an answer, and a
    // 'declined' with `requested_at` set IS the answer. Only an invite (or a
    // row that once held membership) lets a non-friend of the host in.
    const cameByRequest =
      existing !== null &&
      existing.requested_at !== null &&
      (existing.status === "requested" || existing.status === "declined");
    if (existing === null || cameByRequest) {
      if (!(await areFriends(session.host_user_id, userId))) {
        throw new BadRequestError(
          existing?.status === "requested"
            ? "request_pending"
            : "not_friends_with_host",
        );
      }
    }
    if (await isBlockedEitherWay(session.host_user_id, userId)) {
      throw new BadRequestError("blocked");
    }
  }

  // Hoisted out of the transaction so the notify decision below can read it:
  // only a genuine arrival is worth a push. Re-joining a session you're already
  // in (a reconnect, a second tap) must stay silent.
  let previous: string | null = null;

  const client = await db.getClient();
  let arrivalStatus: "active" | "joined" = "joined";
  try {
    await client.query("BEGIN");
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [
      `buddy_session:${sessionId}`,
    ]);

    // Decide arrival status UNDER the lock, from a fresh read: the status
    // fetched above can be a lobby that activateSession (which takes the
    // same lock) has since started. Deciding from the stale read landed the
    // joiner as 'joined' in an 'active' session — invisible to the roster
    // and refused on every progress report.
    const locked = await client.query<{ status: string }>(
      `SELECT status FROM buddy_sessions WHERE id = $1`,
      [sessionId],
    );
    const liveStatus = locked.rows[0]?.status;
    if (liveStatus !== "lobby" && liveStatus !== "active") {
      await client.query("ROLLBACK");
      throw new BadRequestError("session_closed");
    }
    // The walk is already underway, so there is no lobby left to wait in.
    arrivalStatus = liveStatus === "active" ? "active" : "joined";

    const already = await client.query<{ status: string }>(
      `SELECT status FROM buddy_session_participants
        WHERE session_id = $1 AND user_id = $2`,
      [sessionId, userId],
    );
    previous = already.rows[0]?.status ?? null;

    // Only count people occupying a slot. 'left'/'declined' freed theirs and
    // a 'requested' row never held one — until this join, which is the moment
    // a requester who became the host's friend takes a seat.
    if (
      previous === null ||
      previous === "left" ||
      previous === "declined" ||
      previous === "requested"
    ) {
      const countRows = await client.query<{ n: string }>(
        `SELECT COUNT(*)::text AS n FROM buddy_session_participants
          WHERE session_id = $1
            AND status IN ${OCCUPYING_STATUSES_SQL}`,
        [sessionId],
      );
      if (Number(countRows.rows[0]?.n ?? 0) >= BUDDY_MAX_PARTICIPANTS) {
        await client.query("ROLLBACK");
        throw new BadRequestError("session_full");
      }
    }

    // The DO UPDATE guard also lifts a 'joined'/'ready' row to 'active' when
    // the session is already running: that is the state an invitee sits in
    // after tapping Accept on a walk that started without them, and leaving it
    // alone is the same invisibility bug by a different door. 'finished' and
    // 'active' are never rewritten — finished is terminal (re-entering would
    // hand somebody a second mile for a walk they ended), and an active row
    // must not have its `joined_at` or status disturbed by a stray re-join.
    await client.query(
      `INSERT INTO buddy_session_participants
         (session_id, user_id, status, joined_at, location_type)
       VALUES ($1, $2, $3, NOW(), $4)
       ON CONFLICT (session_id, user_id) DO UPDATE
         SET status = $3,
             joined_at = COALESCE(buddy_session_participants.joined_at, NOW()),
             location_type = COALESCE(
               $4::text, buddy_session_participants.location_type)
         WHERE buddy_session_participants.status
                 IN ('invited', 'left', 'declined', 'joined', 'ready', 'requested')`,
      [sessionId, userId, arrivalStatus, opts.locationType ?? null],
    );

    await client.query(
      `UPDATE buddy_sessions SET state_version = state_version + 1 WHERE id = $1`,
      [sessionId],
    );
    await client.query("COMMIT");
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch {
      /* connection-level failure; released below */
    }
    throw e;
  } finally {
    client.release();
  }

  await recordEvent(sessionId, userId, "joined");

  // Tell the host somebody actually showed up. Without this the only way to
  // learn your invite was accepted is to sit watching the lobby repaint — so a
  // host who pockets their phone finds out by texting to ask, which is the
  // coordination this feature exists to remove.
  if (
    previous === null ||
    previous === "invited" ||
    previous === "left" ||
    previous === "declined"
  ) {
    void notifyHostOfJoin(
      sessionId,
      session.host_user_id,
      userId,
      session.status,
    );
  }

  const fresh = await getSessionRow(sessionId);
  if (!fresh) throw new BadRequestError("session_not_found");
  return buildState(fresh);
}

/**
 * "Sam joined your walk" — to the HOST only.
 *
 * Only the host, deliberately: in a five-person lobby, notifying everyone on
 * every arrival means four people get four banners for something they can
 * already see on screen. The host is the one who has to decide when to start,
 * so they're the one who needs to know without looking.
 *
 * Uses `buddy_joined`, which every build carrying the buddy screens already
 * routes (`MainTabView`) — the type existed and simply had nothing sending it.
 * Still gated on `buddy_walks_v1` so a build without those screens can't be
 * handed a push that opens nothing.
 *
 * Never throws: a join must not fail because a push didn't go out.
 */
async function notifyHostOfJoin(
  sessionId: string,
  hostUserId: string | null,
  joinerId: string,
  sessionStatus: string,
): Promise<void> {
  if (!hostUserId || hostUserId === joinerId) return;
  try {
    if (!(await shouldSendNotification(hostUserId, joinerId, "buddy"))) return;
    if (!(await userSupports(hostUserId, CLIENT_FEATURES.buddyWalksV1))) return;

    const rows = await db.query<{
      first_name: string | null;
      username: string | null;
    }>(`SELECT first_name, username FROM users WHERE user_id = $1`, [joinerId]);
    const name = rows[0]?.first_name || rows[0]?.username || "A friend";

    await sendPush(hostUserId, {
      title: "Buddy Walk",
      body:
        sessionStatus === "active"
          ? `${name} joined your walk`
          : `${name} is in — start when you're ready`,
      type: "buddy_joined",
      // String-valued only: shipped builds decode the inbox as
      // [String: String], so one number breaks the whole decode.
      data: { session_id: sessionId, joiner_user_id: joinerId },
    });
  } catch (err) {
    void logError("buddy", "failed to notify host of buddy join", {
      userId: hostUserId,
      context: { sessionId, error: String(err) },
    });
  }
}

export async function declineSession(
  sessionId: string,
  userId: string,
): Promise<void> {
  await db.query(
    `UPDATE buddy_session_participants
        SET status = 'declined'
      WHERE session_id = $1 AND user_id = $2 AND status = 'invited'`,
    [sessionId, userId],
  );
  await bumpVersion(sessionId);
  await recordEvent(sessionId, userId, "declined");
}

export async function leaveSession(
  sessionId: string,
  userId: string,
): Promise<void> {
  await db.query(
    `UPDATE buddy_session_participants
        SET status = 'left'
      WHERE session_id = $1 AND user_id = $2
        AND status NOT IN ('finished', 'left')`,
    [sessionId, userId],
  );
  await bumpVersion(sessionId);
  await recordEvent(sessionId, userId, "left");
  await finalizeIfDue(sessionId);
}

export async function setReady(
  sessionId: string,
  userId: string,
  ready: boolean,
): Promise<BuddySessionState> {
  await db.query(
    `UPDATE buddy_session_participants
        SET status = $3, ready_at = CASE WHEN $3 = 'ready' THEN NOW() ELSE NULL END
      WHERE session_id = $1 AND user_id = $2 AND status IN ('joined', 'ready')`,
    [sessionId, userId, ready ? "ready" : "joined"],
  );
  await bumpVersion(sessionId);

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  return buildState(session);
}

/**
 * Where THIS participant is walking — treadmill or street.
 *
 * Participant-scoped rather than host-scoped, and callable in every phase
 * including mid-walk: it describes where one person is standing, not what the
 * group agreed to do, and somebody who steps onto a treadmill halfway through a
 * shared walk is making a real change to how their phone should be measuring.
 * Deliberately does NOT bump `state_version` on its own — the UPDATE does it in
 * the same statement, so a roster watching a friend switch sees it on the next
 * poll without a second round trip.
 */
export async function setParticipantLocationType(
  sessionId: string,
  userId: string,
  locationType: BuddyLocationType,
): Promise<BuddySessionState> {
  const membership = await participantStatus(sessionId, userId);
  if (membership === null) throw new BadRequestError("not_a_participant");

  await db.query(
    `UPDATE buddy_session_participants
        SET location_type = $3
      WHERE session_id = $1 AND user_id = $2`,
    [sessionId, userId, locationType],
  );
  await bumpVersion(sessionId);

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  return buildState(session);
}

// ─── Start ──────────────────────────────────────────────────────────────

/**
 * Host-only start.
 *
 * `started_at` is set a few seconds in the FUTURE so every client counts down
 * to the same wall-clock instant rather than each starting when its own
 * request happens to return. The guarded UPDATE makes a double-start a no-op:
 * an empty RETURNING means someone already started it.
 */
export async function startSession(
  sessionId: string,
  userId: string,
): Promise<BuddySessionState> {
  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  if (session.host_user_id !== userId) throw new BadRequestError("not_host");

  await activateSession(sessionId, userId);

  const fresh = await getSessionRow(sessionId);
  if (!fresh) throw new BadRequestError("session_not_found");
  return buildState(fresh);
}

export interface UpdateSessionInput {
  mode?: BuddyMode;
  goalValue?: number | null;
  activityType?: BuddyActivityType;
  /** `null` clears the schedule; ABSENT leaves it untouched. */
  scheduledStartAt?: string | null;
  /** Additive only. Removing someone is their own leave/decline. */
  inviteUserIds?: string[];
}

/**
 * Change a lobby's settings, or pull more people into it.
 *
 * The host's mind changes between "let's walk" and "everyone's here", and until
 * now the only way to act on that was to abandon the room and rebuild it —
 * which also invalidated the code they'd already shared. This is the endpoint
 * that makes the lobby a real waiting room rather than a receipt.
 *
 * Three guards, in order:
 *  - host only, because everyone else is looking at these settings;
 *  - lobby only, because changing the mode mid-walk would silently rescore
 *    distance people have already covered;
 *  - and, critically, `WHERE status = 'lobby'` on the UPDATE itself. The status
 *    check above it is a nicety for the error message; THIS is what makes an
 *    edit racing a scheduled promotion lose cleanly. `activateSession` uses the
 *    same guard for the same reason.
 *
 * Goal and mode are validated together through `validateGoal`, so switching to
 * a scored mode demands a goal in the same request and switching back to
 * 'together' drops it — the lobby can never write a state create would reject.
 */
export async function updateSession(
  sessionId: string,
  userId: string,
  patch: UpdateSessionInput,
): Promise<BuddySessionState> {
  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  if (session.host_user_id !== userId) throw new BadRequestError("not_host");
  if (session.status !== "lobby") {
    throw new BadRequestError("session_not_editable");
  }

  const mode = patch.mode ?? (session.mode as BuddyMode);
  // The goal follows the mode it's being validated against: an unchanged mode
  // keeps the stored goal unless the patch names a new one.
  const rawGoal =
    patch.goalValue !== undefined
      ? patch.goalValue
      : patch.mode !== undefined && patch.mode !== session.mode
        ? null
        : (session.goal_value ?? null);
  const goalValue = validateGoal(
    mode,
    rawGoal === null ? null : Number(rawGoal),
  );
  const activityType =
    patch.activityType ?? (session.activity_type as BuddyActivityType);

  const changed = await db.query<{ id: string }>(
    `UPDATE buddy_sessions
        SET mode = $2,
            goal_value = $3,
            activity_type = $4,
            scheduled_start_at = CASE WHEN $5 THEN $6::timestamptz
                                      ELSE scheduled_start_at END,
            -- A moved walk is a different day and a different "15 minutes
            -- before": restamp the day and let the reminder fire again.
            local_date = CASE WHEN $5 THEN ${SESSION_LOCAL_DATE_SQL("$6", "$7")}
                              ELSE local_date END,
            scheduled_reminder_sent_at = CASE WHEN $5 THEN NULL
                                              ELSE scheduled_reminder_sent_at END,
            state_version = state_version + 1
      WHERE id = $1 AND status = 'lobby'
      RETURNING id`,
    [
      sessionId,
      mode,
      goalValue,
      activityType,
      patch.scheduledStartAt !== undefined,
      patch.scheduledStartAt ?? null,
      String(await hostUtcOffsetMinutes(userId)),
    ],
  );
  // Lost the race to a start that landed first. Report it as the state the
  // caller will now see rather than as a failure to write.
  if (changed.length === 0) throw new BadRequestError("session_not_editable");

  if (patch.inviteUserIds?.length) {
    await addInvitees(session, userId, patch.inviteUserIds);
  }

  await recordEvent(sessionId, userId, "updated", { mode, goalValue });

  const fresh = await getSessionRow(sessionId);
  if (!fresh) throw new BadRequestError("session_not_found");
  return buildState(fresh);
}

/**
 * Add people to a lobby that already exists.
 *
 * Reuses `eligibleInvitees` and `notifyInvitees` rather than re-deriving who
 * may be invited — the create path's rules ARE the rules. The participant
 * insert is `ON CONFLICT DO NOTHING`, so re-inviting someone who already
 * joined, declined or left is a no-op and never resurrects them or re-pushes.
 */
async function addInvitees(
  session: BuddySessionRow,
  inviterId: string,
  requested: string[],
): Promise<void> {
  const sessionId = session.id;
  const existing = await db.query<{ user_id: string; status: string }>(
    `SELECT user_id, status FROM buddy_session_participants WHERE session_id = $1`,
    [sessionId],
  );
  const already = new Map(existing.map((row) => [row.user_id, row.status]));
  const asked = Array.from(new Set(requested));

  // Inviting somebody who is standing at the door IS letting them in — the
  // inviter is, by the eligibility rule below, their friend, which is exactly
  // who may answer a request. Without this the tap was a silent no-op (the
  // insert conflicts) and the person stayed waiting.
  const waiting = asked.filter((id) => already.get(id) === "requested");
  for (const requesterId of waiting) {
    await respondToJoinRequest(sessionId, inviterId, requesterId, true);
  }

  const wanted = asked.filter((id) => !already.has(id));
  if (wanted.length === 0) return;
  const occupied = existing.filter((row) =>
    ["invited", "joined", "ready", "active", "finished"].includes(row.status),
  ).length;
  if (occupied + waiting.length + wanted.length > BUDDY_MAX_PARTICIPANTS) {
    throw new BadRequestError("too_many_participants");
  }

  const eligible = await eligibleInvitees(inviterId, wanted);
  if (eligible.length === 0) return;

  await db.query(
    `INSERT INTO buddy_session_participants
       (session_id, user_id, status, invited_by)
     SELECT $1, invitee, 'invited', $2 FROM unnest($3::text[]) AS invitee
     ON CONFLICT (session_id, user_id) DO NOTHING`,
    [sessionId, inviterId, eligible],
  );
  await recordEvent(sessionId, inviterId, "invited", { invitees: eligible });
  void notifyInvitees(
    sessionId,
    session.host_user_id ?? inviterId,
    eligible,
    session.scheduled_start_at,
    inviterId,
    session.status,
  );
}

/** Is this person IN the walk — a member, not an invitee or a requester? */
async function isMember(sessionId: string, userId: string): Promise<boolean> {
  const status = await participantStatus(sessionId, userId);
  return (
    status === "joined" ||
    status === "ready" ||
    status === "active" ||
    status === "finished"
  );
}

/**
 * Pull more people in — from the lobby OR mid-walk, by ANY member.
 *
 * The lobby PATCH is host-only and lobby-only, which made the commonest
 * moment impossible: two friends half a mile in, one says "get Sam", and
 * neither phone had a button. Eligibility is judged against the INVITER
 * (their friend, unblocked, opted in, on a build with the screens), and the
 * invitee then joins through the ordinary door — `joinSession` lets anyone
 * holding an 'invited' row in regardless of who the host is. A running walk
 * lands them 'active' the moment they accept.
 */
export async function inviteToSession(
  sessionId: string,
  inviterId: string,
  userIds: string[],
): Promise<BuddySessionState> {
  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  if (session.status !== "lobby" && session.status !== "active") {
    throw new BadRequestError("session_closed");
  }
  if (!(await isMember(sessionId, inviterId))) {
    throw new BadRequestError("not_a_participant");
  }
  await addInvitees(session, inviterId, userIds);
  await bumpVersion(sessionId);
  const fresh = await getSessionRow(sessionId);
  if (!fresh) throw new BadRequestError("session_not_found");
  return buildState(fresh);
}

/** Members who are friends with `userId` — the people who can vouch for them. */
async function memberFriendsOf(
  sessionId: string,
  userId: string,
): Promise<string[]> {
  const rows = await db.query<{ user_id: string }>(
    `SELECT m.user_id
       FROM buddy_session_participants m
      WHERE m.session_id = $1
        AND m.user_id <> $2
        AND m.status IN ('joined', 'ready', 'active', 'finished')
        AND EXISTS (
          SELECT 1 FROM friendships f
           WHERE f.status = 'accepted'
             AND ((f.user_id = $2 AND f.friend_id = m.user_id)
               OR (f.user_id = m.user_id AND f.friend_id = $2)))
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $2 AND b.blocked_id = m.user_id)
              OR (b.blocker_id = m.user_id AND b.blocked_id = $2))`,
    [sessionId, userId],
  );
  return rows.map((r) => r.user_id);
}

/**
 * Ask to be let into a walk you weren't invited to.
 *
 * The rule is "a friend of somebody IN it": joinSession's door is friendship
 * with the HOST, and that made every mixed group a dead end — you see your
 * friend is out with people you don't know, and the only move was to text
 * them and hope they find the invite button. This parks the asker as
 * 'requested' — not a member, holding no slot, invisible to every roster
 * read — and tells the host and the members who know them. Any of those can
 * answer; approval turns the row into an ordinary 'invited' one, so the rest
 * of the flow (the invite pill, the push type every build routes, the join)
 * is exactly what already ships.
 *
 * Deliberately NOT a bypass for the host-friend case: someone the host is
 * friends with is told to walk straight in (`join_directly`), or the door
 * would put a wait in front of people who never had one.
 */
export async function requestToJoin(
  sessionId: string,
  userId: string,
): Promise<{ status: "requested" }> {
  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  if (session.status !== "lobby" && session.status !== "active") {
    throw new BadRequestError("session_closed");
  }
  if (session.host_user_id === userId) throw new BadRequestError("already_in");
  if (
    session.host_user_id &&
    (await isBlockedEitherWay(session.host_user_id, userId))
  ) {
    throw new BadRequestError("blocked");
  }

  const existingRows = await db.query<{
    status: string;
    requested_at: string | null;
  }>(
    `SELECT status, requested_at FROM buddy_session_participants
      WHERE session_id = $1 AND user_id = $2`,
    [sessionId, userId],
  );
  const existing = existingRows[0] ?? null;
  if (existing?.status === "requested") return { status: "requested" };
  if (existing?.status === "invited") throw new BadRequestError("already_invited");
  if (
    existing &&
    ["joined", "ready", "active", "finished"].includes(existing.status)
  ) {
    throw new BadRequestError("already_in");
  }
  // Refused once is refused: the row keeps `requested_at`, so this is the
  // answer to THEIR ask and not an invite they turned down.
  if (existing?.status === "declined" && existing.requested_at !== null) {
    throw new BadRequestError("request_declined");
  }

  if (session.host_user_id && (await areFriends(session.host_user_id, userId))) {
    throw new BadRequestError("join_directly");
  }
  const vouchers = await memberFriendsOf(sessionId, userId);
  if (vouchers.length === 0) throw new BadRequestError("no_friends_in_walk");

  const open = await db.query<{ ok: boolean }>(
    `SELECT ${JOINABLE_WINDOW_SQL("s")} AS ok FROM buddy_sessions s WHERE s.id = $1`,
    [sessionId],
  );
  if (open[0]?.ok !== true) throw new BadRequestError("session_closed");

  const countRows = await db.query<{ n: string }>(
    `SELECT COUNT(*)::text AS n FROM buddy_session_participants
      WHERE session_id = $1 AND status IN ${OCCUPYING_STATUSES_SQL}`,
    [sessionId],
  );
  if (Number(countRows[0]?.n ?? 0) >= BUDDY_MAX_PARTICIPANTS) {
    throw new BadRequestError("session_full");
  }

  await db.query(
    `INSERT INTO buddy_session_participants
       (session_id, user_id, status, requested_at)
     VALUES ($1, $2, 'requested', NOW())
     ON CONFLICT (session_id, user_id) DO UPDATE
       SET status = 'requested', requested_at = NOW()
       WHERE buddy_session_participants.status IN ('left', 'declined')`,
    [sessionId, userId],
  );
  await bumpVersion(sessionId);
  await recordEvent(sessionId, userId, "join_requested");
  void notifyJoinRequest(session, userId, vouchers);
  return { status: "requested" };
}

/**
 * "Sam wants to join your walk" — to the host and to the members who know
 * them, i.e. exactly the people who can answer. Gated PER DEVICE on
 * `buddy_join_request_v1`: the type is new, and a build that doesn't route
 * it would show a banner that opens nothing. Those people still see the
 * request the next time their lobby or tracker polls.
 */
async function notifyJoinRequest(
  session: BuddySessionRow,
  requesterId: string,
  vouchers: string[],
): Promise<void> {
  try {
    const name = await displayName(requesterId);
    const targets = Array.from(
      new Set(
        [session.host_user_id, ...vouchers].filter(
          (id): id is string => !!id && id !== requesterId,
        ),
      ),
    );
    const recipients = await allowedRecipients(targets, requesterId, "buddy");
    await Promise.all(
      recipients.map(async (recipientId) => {
        if (
          !(await userSupports(recipientId, CLIENT_FEATURES.buddyJoinRequestV1))
        ) {
          return;
        }
        await sendPush(recipientId, {
          title: "Buddy Walk",
          body:
            recipientId === session.host_user_id
              ? `${name} wants to join your walk — tap to let them in`
              : `${name} wants to join the walk — you can let them in`,
          type: "buddy_join_request",
          data: { session_id: session.id, requester_user_id: requesterId },
        });
      }),
    );
  } catch (err) {
    void logError("buddy", "failed to notify buddy join request", {
      userId: requesterId,
      context: { sessionId: session.id, error: String(err) },
    });
  }
}

/**
 * Answer someone at the door. The host always may; so may any member who is
 * the requester's friend — the same people who were told.
 *
 * Yes becomes an ordinary 'invited' row (stamped with who let them in), and
 * the requester gets `buddy_invite`, the push every build already routes, so
 * their tap lands in the same join flow an invite does. No is silent, Instagram
 * style — being told "no" by name is worse than a request that just lapses —
 * and the row keeps `requested_at`, which is what stops a re-ask and what
 * keeps a refused requester from walking in through the invitee door.
 */
export async function respondToJoinRequest(
  sessionId: string,
  approverId: string,
  requesterId: string,
  accept: boolean,
): Promise<BuddySessionState> {
  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  if (session.status !== "lobby" && session.status !== "active") {
    throw new BadRequestError("session_closed");
  }
  const isHost = session.host_user_id === approverId;
  if (!isHost) {
    if (!(await isMember(sessionId, approverId))) {
      throw new BadRequestError("not_a_participant");
    }
    if (!(await areFriends(approverId, requesterId))) {
      throw new BadRequestError("not_allowed");
    }
  }

  const changed = await db.query<{ user_id: string }>(
    accept
      ? `UPDATE buddy_session_participants
            SET status = 'invited', invited_by = $3
          WHERE session_id = $1 AND user_id = $2 AND status = 'requested'
          RETURNING user_id`
      : `UPDATE buddy_session_participants
            SET status = 'declined'
          WHERE session_id = $1 AND user_id = $2 AND status = 'requested'
            AND $3::text IS NOT NULL
          RETURNING user_id`,
    [sessionId, requesterId, approverId],
  );
  if (changed.length === 0) throw new BadRequestError("request_not_found");

  await bumpVersion(sessionId);
  await recordEvent(
    sessionId,
    approverId,
    accept ? "join_approved" : "join_declined",
    { requester: requesterId },
  );
  if (accept) void notifyRequestApproved(session, approverId, requesterId);
  else void notifyRequestRefused(session, approverId, requesterId);

  const fresh = await getSessionRow(sessionId);
  if (!fresh) throw new BadRequestError("session_not_found");
  return buildState(fresh);
}

/**
 * "Not this time" — the asker was otherwise left with a pill that quietly
 * changed. Its own type, gated on the same feature string the ask itself
 * needs (a device that could send the request can route the answer), so a
 * shipped build that never asked is never handed a type it can't open.
 */
async function notifyRequestRefused(
  session: BuddySessionRow,
  approverId: string,
  requesterId: string,
): Promise<void> {
  try {
    if (!(await userSupports(requesterId, CLIENT_FEATURES.buddyJoinRequestV1))) return;
    const recipients = await allowedRecipients([requesterId], approverId, "buddy");
    if (recipients.length === 0) return;
    const name = await displayName(approverId);
    await sendPush(requesterId, {
      title: "Buddy Walk",
      body: `Not this time — ${name} kept the walk as it is. Start your own and they can join you.`,
      type: "buddy_join_refused",
      data: {
        session_id: session.id,
        host_user_id: session.host_user_id ?? approverId,
        responder_user_id: approverId,
      },
    });
  } catch (err) {
    void logError("buddy", "failed to notify refused buddy request", {
      userId: requesterId,
      context: { sessionId: session.id, error: String(err) },
    });
  }
}

/** "Sam let you in — tap to join" — `buddy_invite`, which every build routes. */
async function notifyRequestApproved(
  session: BuddySessionRow,
  approverId: string,
  requesterId: string,
): Promise<void> {
  try {
    const recipients = await allowedRecipients([requesterId], approverId, "buddy");
    if (recipients.length === 0) return;
    const name = await displayName(approverId);
    await sendPush(requesterId, {
      title: "Buddy Walk",
      body:
        session.status === "active"
          ? `${name} let you in — tap to join the walk`
          : `${name} let you in — tap to join the lobby`,
      type: "buddy_invite",
      category: "BUDDY_INVITE",
      data: {
        session_id: session.id,
        host_user_id: session.host_user_id ?? approverId,
        inviter_user_id: approverId,
      },
    });
  } catch (err) {
    void logError("buddy", "failed to notify approved buddy request", {
      userId: requesterId,
      context: { sessionId: session.id, error: String(err) },
    });
  }
}


/**
 * Flip a lobby to active. The single place a session ever starts — a manual
 * host start and a scheduled promotion are the same operation with different
 * triggers, and having two copies of this UPDATE is how they drift apart.
 *
 * The `WHERE status = 'lobby'` guard makes it naturally idempotent: a promotion
 * racing a manual start (or two cron ticks racing each other) means whichever
 * loses updates nothing and sends nothing. Returns whether THIS call started it.
 */
async function activateSession(
  sessionId: string,
  actorUserId: string | null,
): Promise<boolean> {
  // Under the session's advisory lock, in ONE transaction with the roster
  // flip: a join that lands between the status flip and the roster update
  // used to be left 'joined' in an 'active' session.
  const client = await db.getClient();
  let started = false;
  try {
    await client.query("BEGIN");
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [
      `buddy_session:${sessionId}`,
    ]);
    const flipped = await client.query<{ id: string }>(
      `UPDATE buddy_sessions
          SET status = 'active',
              started_at = NOW() + ($2 || ' seconds')::interval,
              ends_at = CASE
                WHEN mode = 'race_time' AND goal_value IS NOT NULL
                  THEN NOW() + ($2 || ' seconds')::interval
                       + (goal_value || ' minutes')::interval
                ELSE NULL
              END,
              state_version = state_version + 1
        WHERE id = $1 AND status = 'lobby'
        RETURNING id`,
      [sessionId, String(BUDDY_START_COUNTDOWN_SECONDS)],
    );
    started = flipped.rows.length > 0;
    if (started) {
      // Everyone still in the lobby becomes active. Invitees who never
      // responded are left behind rather than dragged in.
      await client.query(
        `UPDATE buddy_session_participants
            SET status = 'active'
          WHERE session_id = $1 AND status IN ('joined', 'ready')`,
        [sessionId],
      );
    }
    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
  if (!started) return false;
  await recordEvent(sessionId, actorUserId, "started");
  void notifySessionStarted(sessionId, actorUserId);
  return true;
}

/**
 * Host calls the whole thing off.
 *
 * The missing exit. A host who opened a lobby by mistake, or picked the wrong
 * mode, or whose friend just texted "can't make it", had exactly one way out —
 * Leave — which abandons a room that then sits `lobby` for three hours holding
 * its join code, still listed to every invitee as a walk that is about to
 * happen, and still promotable by the scheduled-start cron. Cancelling is what
 * they actually meant.
 *
 * Two windows, both before anybody has moved:
 *  - `lobby`, the obvious one;
 *  - `active` while `started_at` is still in the FUTURE, i.e. during the shared
 *    countdown. That is the exact moment "wait, no" happens, and until now the
 *    countdown was an eight-second commitment with no brakes.
 *
 * Never after the walk is genuinely underway: from there the honest verb is
 * finish (which keeps everyone's miles) or leave, and letting one person's
 * cancel wipe a walk other people are recording would destroy their data.
 *
 * The window lives in the UPDATE's own WHERE, not just in a pre-check, for the
 * same reason `updateSession`'s does: a cancel racing the countdown's elapse
 * has to lose cleanly rather than cancel a walk that is already moving.
 */
export async function cancelSession(
  sessionId: string,
  userId: string,
): Promise<BuddySessionState> {
  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  if (session.host_user_id !== userId) throw new BadRequestError("not_host");

  if (!(await cancelInternal(sessionId, userId, true))) {
    throw new BadRequestError("session_not_cancellable");
  }

  const fresh = await getSessionRow(sessionId);
  if (!fresh) throw new BadRequestError("session_not_found");
  return buildState(fresh);
}

/**
 * The one cancel: a host calling it off (`notify`), or the sweep retiring a
 * lobby nobody started / a promoted walk nobody took (silent — there is no
 * news in a walk that didn't happen). Returns false when the session was
 * not in a cancellable state.
 */
async function cancelInternal(
  sessionId: string,
  actorUserId: string | null,
  notify: boolean,
): Promise<boolean> {
  const cancelled = await db.query<{ id: string; host_user_id: string }>(
    `UPDATE buddy_sessions
        SET status = 'cancelled', ended_at = NOW(),
            state_version = state_version + 1
      WHERE id = $1
        AND ($2::text IS NULL OR host_user_id = $2::text)
        AND (status = 'lobby'
             OR (status = 'active' AND started_at > NOW())
             -- The sweep's case: a running walk nobody reported a metre on.
             OR ($2::text IS NULL AND status = 'active'))
      RETURNING id, host_user_id`,
    [sessionId, actorUserId],
  );
  if (cancelled.length === 0) return false;

  // Everyone still in the room is released. Deliberately NOT 'finished':
  // finished is what the history reads, and a walk nobody took must never
  // appear in anyone's archive.
  await db.query(
    `UPDATE buddy_session_participants
        SET status = 'left'
      WHERE session_id = $1
        AND status IN ('invited', 'joined', 'ready', 'active', 'requested')`,
    [sessionId],
  );

  await recordEvent(sessionId, actorUserId, "cancelled");
  if (notify) {
    void notifySessionCancelled(sessionId, cancelled[0].host_user_id);
  }
  return true;
}

/**
 * "Sam called off the walk" — to everyone who had said yes.
 *
 * Read from `buddy_session_events` rather than the participant rows, because
 * `cancelSession` has already rewritten every one of those to 'left' by the
 * time this runs. Invitees who never answered are skipped: their invite simply
 * stops existing, and telling somebody a walk they ignored is off is noise.
 */
async function notifySessionCancelled(
  sessionId: string,
  hostUserId: string,
): Promise<void> {
  try {
    const rows = await db.query<{ user_id: string }>(
      `SELECT DISTINCT e.user_id
         FROM buddy_session_events e
        WHERE e.session_id = $1
          AND e.kind = 'joined'
          AND e.user_id IS NOT NULL
          AND e.user_id <> $2`,
      [sessionId, hostUserId],
    );
    if (rows.length === 0) return;

    const hostRows = await db.query<{
      first_name: string | null;
      username: string | null;
    }>(`SELECT first_name, username FROM users WHERE user_id = $1`, [
      hostUserId,
    ]);
    const hostName =
      hostRows[0]?.first_name || hostRows[0]?.username || "The host";

    for (const row of rows) {
      if (!(await shouldSendNotification(row.user_id, hostUserId, "buddy"))) {
        continue;
      }
      if (!(await userSupports(row.user_id, CLIENT_FEATURES.buddyWalksV1))) {
        continue;
      }
      await sendPush(row.user_id, {
        title: "Buddy Walk cancelled",
        body: `${hostName} called off the walk`,
        // Reuses a type every build carrying the buddy screens already routes.
        // A new string would tap to nothing on the builds that are out.
        type: "buddy_finished",
        // String-valued only: shipped builds decode the inbox's `data` as
        // [String: String], so one number breaks the whole decode.
        data: { session_id: sessionId, cancelled: "true" },
      });
    }
  } catch (err) {
    void logError("buddy", "failed to notify session cancel", {
      userId: hostUserId,
      context: { sessionId, error: String(err) },
    });
  }
}

/**
 * Start a scheduled session whose time has arrived.
 *
 * Called BOTH lazily (from every state read) and from the cron, the same shape
 * `finalizeIfDue` uses. The lazy path makes a session start the instant someone
 * is looking at the lobby; the cron makes it start on time when nobody is.
 */
export async function promoteScheduledIfDue(sessionId: string): Promise<void> {
  const due = await db.query<{ id: string }>(
    `SELECT id FROM buddy_sessions
      WHERE id = $1 AND status = 'lobby'
        AND scheduled_start_at IS NOT NULL
        AND scheduled_start_at <= NOW()`,
    [sessionId],
  );
  if (due.length === 0) return;
  await activateSession(sessionId, null);
}

/**
 * Cron sweep: promote every scheduled session that's due, and send the
 * heads-up push for ones starting soon.
 *
 * The reminder is claim-then-send against `scheduled_reminder_sent_at` — the
 * same pattern h2h_matchups.notified_at uses — so overlapping containers during
 * a deploy can't double-push. Claiming BEFORE sending is deliberate: a missed
 * reminder is a small disappointment, a duplicate one is spam.
 */
export async function promoteDueScheduledSessions(): Promise<number> {
  const due = await db.query<{ id: string }>(
    `SELECT id FROM buddy_sessions
      WHERE status = 'lobby'
        AND scheduled_start_at IS NOT NULL
        AND scheduled_start_at <= NOW()
        -- A session whose time passed hours ago was abandoned, not delayed;
        -- the lobby sweep below cancels those rather than starting a walk
        -- nobody is standing by for.
        AND scheduled_start_at > NOW() - INTERVAL '30 minutes'`,
  );
  for (const row of due) {
    try {
      await activateSession(row.id, null);
    } catch (err) {
      void logError("buddy", "failed to promote scheduled buddy session", {
        context: { sessionId: row.id, error: String(err) },
      });
    }
  }

  await sendScheduledReminders();
  return due.length;
}

/** "Your buddy walk starts in 15 minutes", exactly once per session. */
async function sendScheduledReminders(): Promise<void> {
  const claimed = await db.query<{ id: string; scheduled_start_at: string }>(
    `UPDATE buddy_sessions
        SET scheduled_reminder_sent_at = NOW()
      WHERE status = 'lobby'
        AND scheduled_start_at IS NOT NULL
        AND scheduled_reminder_sent_at IS NULL
        AND scheduled_start_at <= NOW() + INTERVAL '15 minutes'
        AND scheduled_start_at > NOW()
        -- A walk booked (or a routine spawned) inside the last 15 minutes
        -- has JUST sent its invite; a reminder on its heels is the same push
        -- twice on one tick.
        AND created_at < NOW() - INTERVAL '15 minutes'
      RETURNING id, scheduled_start_at`,
  );

  for (const session of claimed) {
    try {
      const participants = await db.query<{ user_id: string; status: string }>(
        `SELECT user_id, status FROM buddy_session_participants
          WHERE session_id = $1 AND status IN ('invited', 'joined', 'ready')`,
        [session.id],
      );
      for (const p of participants) {
        if (!(await shouldSendNotification(p.user_id, null, "buddy"))) continue;
        await sendPush(p.user_id, {
          title: "Buddy Walk soon",
          body: "Your walk starts in about 15 minutes",
          type: "buddy_invite",
          // Join / Not now buttons only for someone who hasn't answered;
          // to a person already in the room they are a question already
          // answered.
          ...(p.status === "invited" ? { category: "BUDDY_INVITE" } : {}),
          data: { session_id: session.id },
        });
      }
    } catch (err) {
      void logError("buddy", "failed to send scheduled buddy reminder", {
        context: { sessionId: session.id, error: String(err) },
      });
    }
  }
}

async function notifySessionStarted(
  sessionId: string,
  hostUserId: string | null,
): Promise<void> {
  try {
    const rows = await db.query<{ user_id: string }>(
      // $2 IS NULL on a scheduled promotion (no human actor). Without the
      // guard, `user_id <> NULL` is NULL for every row and nobody is told
      // their walk just started.
      `SELECT user_id FROM buddy_session_participants
        WHERE session_id = $1 AND status = 'active'
          AND ($2::text IS NULL OR user_id <> $2)`,
      [sessionId, hostUserId],
    );
    const recipients = await allowedRecipients(
      rows.map((r) => r.user_id),
      hostUserId,
      "buddy",
    );
    await Promise.all(
      recipients.map((userId) =>
        sendPush(userId, {
          title: "Buddy Walk started",
          body: "Your buddy walk is underway — get moving!",
          type: "buddy_started",
          data: { session_id: sessionId },
        }),
      ),
    );
  } catch (err) {
    void logError("buddy", "failed to notify session start", {
      userId: hostUserId,
      context: { sessionId, error: String(err) },
    });
  }
}

// ─── Progress ───────────────────────────────────────────────────────────

/**
 * Record one participant's live progress and hand back the whole roster.
 *
 * The response carries the full snapshot on purpose: a 45-minute walk polling
 * separately every 3s is ~900 extra round trips per participant. Folding the
 * read into the write halves the traffic and removes an entire class of
 * "my poll raced my post" ordering bugs.
 *
 * Distance is CLAMPED, never rejected. Rejecting would freeze a participant
 * whose GPS burped, which reads as a bug to every other person watching the
 * roster.
 *
 * The ceiling is absolute: total distance can never exceed BUDDY_MAX_SPEED_MPS
 * sustained since the session STARTED (the same teleport cap the iOS
 * WorkoutLocationManager enforces locally). Deliberately not derived from the
 * gap since the previous report — that would punish a legitimate catch-up
 * report after the app spent ten minutes backgrounded, and would cap the very
 * first report of a long session at a few seconds' worth of travel.
 */
export async function recordProgress(
  sessionId: string,
  userId: string,
  distanceMiles: number,
  durationSeconds: number,
  /**
   * The walker's MANUAL pause, additive. Undefined from a client that predates
   * the flag, and written as NULL — which is that client's behaviour today, so
   * it can neither set nor strand the state.
   */
  paused?: boolean,
): Promise<BuddySessionState> {
  if (!Number.isFinite(distanceMiles) || distanceMiles < 0) {
    throw new BadRequestError("invalid_distance");
  }
  if (!Number.isFinite(durationSeconds) || durationSeconds < 0) {
    throw new BadRequestError("invalid_duration");
  }

  let status = await participantStatus(sessionId, userId);
  if (status === null) throw new BadRequestError("not_a_participant");
  if (status === "joined" || status === "ready") {
    // Belt and braces for the join/promotion race: someone reporting miles
    // is by definition walking, so a 'joined' row in a running session is
    // lifted rather than refused for the rest of the walk.
    const lifted = await db.query<{ status: string }>(
      `UPDATE buddy_session_participants p
          SET status = 'active'
         FROM buddy_sessions s
        WHERE p.session_id = $1 AND p.user_id = $2
          AND p.status IN ('joined', 'ready')
          AND s.id = p.session_id AND s.status = 'active'
        RETURNING p.status`,
      [sessionId, userId],
    );
    if (lifted.length > 0) status = "active";
  }
  if (status !== "active") throw new BadRequestError("not_active");

  const maxMilesPerSecond = BUDDY_MAX_SPEED_MPS / METERS_PER_MILE;

  await db.query(
    `UPDATE buddy_session_participants p
        SET distance_miles = GREATEST(
              p.distance_miles,
              LEAST(
                $3::double precision,
                -- Absolute physical ceiling: max sustained speed since the
                -- session started. GREATEST(..., 1) keeps the bound positive
                -- during the pre-start countdown, when started_at is still in
                -- the future.
                $5::double precision * GREATEST(
                  EXTRACT(EPOCH FROM (NOW() - s.started_at)),
                  1
                )
              )
            ),
            duration_seconds = GREATEST(p.duration_seconds, $4::integer),
            -- NOT clamped like the two above: a pause is a state, and the
            -- newest report is always the truth about it.
            is_paused = $6::boolean,
            last_progress_at = NOW()
       FROM buddy_sessions s
      WHERE p.session_id = $1 AND p.user_id = $2 AND p.status = 'active'
        AND s.id = p.session_id AND s.started_at IS NOT NULL`,
    [
      sessionId,
      userId,
      distanceMiles,
      Math.floor(durationSeconds),
      maxMilesPerSecond,
      paused === undefined ? null : paused,
    ],
  );

  await bumpVersion(sessionId);
  await finalizeIfDue(sessionId);

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  return buildState(session);
}

// ─── Finish & finalize ──────────────────────────────────────────────────

export async function finishParticipation(
  sessionId: string,
  userId: string,
): Promise<BuddySessionState> {
  await db.query(
    `UPDATE buddy_session_participants
        SET status = 'finished', finished_at = NOW()
      WHERE session_id = $1 AND user_id = $2 AND status = 'active'`,
    [sessionId, userId],
  );
  // Link NOW, not at close. The usual order on a phone is HealthKit save →
  // observer sync (reconcileBuddySessions: participant still 'active', no
  // stamp) → this Finish — so the workout was on the server, route and all,
  // and stayed unlinked until the LAST person closed the walk. On a four-
  // person walk that is however long the slowest walker takes, and the whole
  // time this person's route was missing from the card and their post had
  // no workout to take its colour from.
  await linkSyncedWorkouts(sessionId);
  await bumpVersion(sessionId);
  await recordEvent(sessionId, userId, "finished");
  await finalizeIfDue(sessionId, userId);

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  return buildState(session);
}

/**
 * Close the session if it is due, and stamp placements.
 *
 * Called from every state read and from the hourly cron as a backstop — the
 * same lazy "recompute on read" shape competitions use for standings, which is
 * what lets a race_time session end punctually without a per-minute cron.
 *
 * Idempotent: the guarded UPDATE on status makes a concurrent second call a
 * no-op.
 */
export async function finalizeIfDue(
  sessionId: string,
  actorUserId: string | null = null,
): Promise<void> {
  const session = await getSessionRow(sessionId);
  if (!session || session.status !== "active") return;

  const participants = await db.query<{
    user_id: string;
    status: string;
    distance_miles: number;
  }>(
    `SELECT user_id, status, distance_miles
       FROM buddy_session_participants
      WHERE session_id = $1 AND status IN ('active', 'finished')`,
    [sessionId],
  );

  if (participants.length === 0) {
    await closeSession(sessionId, null, actorUserId);
    return;
  }

  const everyoneDone = participants.every((p) => p.status === "finished");
  const timeUp =
    session.ends_at !== null &&
    new Date(session.ends_at).getTime() <= Date.now();

  let goalReached = false;
  const goal = session.goal_value === null ? null : Number(session.goal_value);
  if (goal !== null) {
    if (session.mode === "coop_goal") {
      const total = participants.reduce(
        (sum, p) => sum + Number(p.distance_miles || 0),
        0,
      );
      goalReached = total >= goal;
    } else if (session.mode === "race_goal") {
      goalReached = participants.some(
        (p) => Number(p.distance_miles || 0) >= goal,
      );
    }
  }

  if (!everyoneDone && !timeUp && !goalReached) return;

  // Winner: furthest distance. 'together' and 'coop_goal' are cooperative and
  // deliberately have no winner — declaring one would undercut the whole point.
  let winnerId: string | null = null;
  if (session.mode === "race_goal" || session.mode === "race_time") {
    const ranked = [...participants].sort(
      (a, b) => Number(b.distance_miles || 0) - Number(a.distance_miles || 0),
    );
    const top = ranked[0];
    const runnerUp = ranked[1];
    // Compare at 2dp — the same display precision the roster shows, and the
    // same rule H2H uses. A dead heat awards NOBODY rather than letting float
    // noise or sort order silently pick a winner.
    const isTie =
      runnerUp !== undefined &&
      Number(top.distance_miles || 0).toFixed(2) ===
        Number(runnerUp.distance_miles || 0).toFixed(2);
    winnerId = top && !isTie ? top.user_id : null;
  }

  await closeSession(sessionId, winnerId, actorUserId);
}

async function closeSession(
  sessionId: string,
  winnerId: string | null,
  actorUserId: string | null = null,
): Promise<void> {
  const closed = await db.query<{ id: string }>(
    `UPDATE buddy_sessions
        SET status = 'completed', ended_at = NOW(), winner_user_id = $2,
            state_version = state_version + 1
      WHERE id = $1 AND status = 'active'
      RETURNING id`,
    [sessionId, winnerId],
  );
  if (closed.length === 0) return; // someone else finalized first

  await db.query(
    `UPDATE buddy_session_participants
        SET status = 'finished',
            finished_at = COALESCE(finished_at, NOW())
      WHERE session_id = $1 AND status = 'active'`,
    [sessionId],
  );

  // Placement by live distance. reconcileBuddySessions may restamp this once
  // the real workouts land.
  await db.query(
    `UPDATE buddy_session_participants p
        SET place = ranked.rn
       FROM (
         SELECT user_id,
                RANK() OVER (ORDER BY distance_miles DESC) AS rn
           FROM buddy_session_participants
          WHERE session_id = $1 AND status = 'finished'
       ) ranked
      WHERE p.session_id = $1 AND p.user_id = ranked.user_id`,
    [sessionId],
  );

  // Link every finisher whose real workout already synced (the host who
  // finished on the Watch and synced before tapping Finish, or whose upload
  // landed while a friend was still out), then rank on the real numbers.
  await linkSyncedWorkouts(sessionId);

  await recordEvent(sessionId, winnerId, "completed", { winnerId });
  void notifySessionFinished(sessionId, actorUserId);

  // Buddy medals are aggregate-driven; recompute for everyone who took part.
  try {
    const rows = await db.query<{ user_id: string }>(
      `SELECT user_id FROM buddy_session_participants
        WHERE session_id = $1 AND status = 'finished'`,
      [sessionId],
    );
    for (const row of rows) {
      void evaluateSocialBadgesForUser(row.user_id);
    }
  } catch {
    /* badge evaluation is best-effort and must never fail a session close */
  }
}

async function notifySessionFinished(
  sessionId: string,
  actorUserId: string | null = null,
): Promise<void> {
  try {
    const rows = await db.query<{ user_id: string }>(
      `SELECT user_id FROM buddy_session_participants
        WHERE session_id = $1 AND status = 'finished'`,
      [sessionId],
    );
    // The person whose Finish closed the walk is looking at the recap
    // already; everyone else gets it subject to their buddy switch.
    const recipients = await allowedRecipients(
      rows.map((r) => r.user_id).filter((id) => id !== actorUserId),
      null,
      "buddy",
    );
    for (const userId of recipients) {
      await sendPush(userId, {
        title: "Buddy Walk complete",
        body: "See how your crew did",
        type: "buddy_finished",
        data: { session_id: sessionId },
      });
    }
  } catch (err) {
    void logError("buddy", "failed to notify session finish", {
      context: { sessionId, error: String(err) },
    });
  }
}

// ─── Reconciliation with the real workout ───────────────────────────────

/**
 * Stamp the authoritative result once a participant's real workout syncs.
 *
 * Live `distance_miles` is display state accumulated from 5-second reports; the
 * truth is the HKWorkout that lands through the normal upload path. Called
 * fire-and-forget from workoutController.uploadWorkouts, next to
 * reconcileStreakFeaturesOnUpload.
 *
 * Matching is by time-window overlap: the workout must have ended at or after
 * the session started, and started before the session ended (with slack for a
 * late finish tap).
 */
export async function reconcileBuddySessions(
  userId: string,
  uploadedWorkoutIds: string[],
): Promise<void> {
  if (uploadedWorkoutIds.length === 0) return;

  try {
    // The session need not be COMPLETED: in a two-person walk the first
    // finisher's HKWorkout syncs seconds after they tap Finish, while the
    // friend is still out — and nothing re-ran this once the walk ended, so
    // that person stayed "not synced" (no route, no final distance) for
    // good. A finished participant of a still-running walk links now, and
    // closeSession links whatever synced before it. 72 hours, not 12: a
    // Watch that syncs the next morning still lands.
    await db.query(
      `UPDATE buddy_session_participants p
          SET workout_id = w.workout_id,
              final_distance_miles = w.distance
         FROM buddy_sessions s, workouts w
        WHERE p.session_id = s.id
          AND p.user_id = $1
          AND p.workout_id IS NULL
          AND p.status = 'finished'
          AND s.status IN ('active', 'completed')
          AND s.started_at IS NOT NULL
          AND s.started_at > NOW() - INTERVAL '72 hours'
          AND w.workout_id = ANY($2::varchar[])
          AND w.user_id = $1
          AND w.deleted_at IS NULL
          AND w.exclusion_reason IS NULL
          AND w.device_end_date >= s.started_at
          AND (w.device_end_date - (w.total_duration || ' seconds')::interval)
                <= COALESCE(s.ended_at, NOW()) + INTERVAL '10 minutes'`,
      [userId, uploadedWorkoutIds],
    );

    await linkSessionPosts(userId);

    // Re-rank any session this just touched, now using reconciled numbers where
    // they exist and live numbers where they don't yet.
    await db.query(
      `UPDATE buddy_session_participants p
          SET place = ranked.rn
         FROM (
           SELECT bp.session_id, bp.user_id,
                  RANK() OVER (
                    PARTITION BY bp.session_id
                    ORDER BY COALESCE(bp.final_distance_miles, bp.distance_miles) DESC
                  ) AS rn
             FROM buddy_session_participants bp
            WHERE bp.session_id IN (
                    SELECT session_id FROM buddy_session_participants
                     WHERE user_id = $1 AND workout_id = ANY($2::varchar[])
                  )
              AND bp.status = 'finished'
         ) ranked
        WHERE p.session_id = ranked.session_id AND p.user_id = ranked.user_id`,
      [userId, uploadedWorkoutIds],
    );
  } catch (err) {
    void logError("buddy", "failed to reconcile buddy sessions", {
      userId,
      context: { error: String(err) },
    });
  }
}

/**
 * Link every finished participant of ONE session to their already-synced
 * workout — the close-time twin of reconcileBuddySessions, for the person
 * whose upload landed before the walk was over (or before they tapped
 * Finish). Picks the counted workout that overlaps the session most, then
 * re-ranks on the real numbers.
 */
export async function linkSyncedWorkouts(sessionId: string): Promise<void> {
  try {
    await db.query(
      `UPDATE buddy_session_participants p
          SET workout_id = best.workout_id,
              final_distance_miles = best.distance
         FROM (
           SELECT DISTINCT ON (bp.user_id) bp.user_id, w.workout_id, w.distance
             FROM buddy_session_participants bp
             JOIN buddy_sessions s ON s.id = bp.session_id
             JOIN workouts w
               ON w.user_id = bp.user_id
              AND w.deleted_at IS NULL
              AND w.exclusion_reason IS NULL
              AND w.device_end_date >= s.started_at
              AND (w.device_end_date - (w.total_duration || ' seconds')::interval)
                    <= COALESCE(s.ended_at, NOW()) + INTERVAL '10 minutes'
            WHERE bp.session_id = $1
              AND bp.status = 'finished'
              AND bp.workout_id IS NULL
              AND s.started_at IS NOT NULL
            ORDER BY bp.user_id, w.device_end_date DESC
         ) best
        WHERE p.session_id = $1
          AND p.user_id = best.user_id
          AND p.workout_id IS NULL`,
      [sessionId],
    );
    await linkSessionPosts(null, sessionId);
    await db.query(
      `UPDATE buddy_session_participants p
          SET place = ranked.rn
         FROM (
           SELECT bp.user_id,
                  RANK() OVER (
                    ORDER BY COALESCE(bp.final_distance_miles, bp.distance_miles) DESC
                  ) AS rn
             FROM buddy_session_participants bp
            WHERE bp.session_id = $1 AND bp.status = 'finished'
         ) ranked
        WHERE p.session_id = $1 AND p.user_id = ranked.user_id`,
      [sessionId],
    );
  } catch (err) {
    void logError("buddy", "failed to link synced workouts at close", {
      context: { sessionId, error: String(err) },
    });
  }
}

/**
 * Give a walk's posts the workout they were made without.
 *
 * A post made from the recap in the seconds before HealthKit publishes the
 * walk carries no `workout_id` — and everything on the card keys on it: the
 * activity colour (a NULL type draws red), the author's route, the day-rollup
 * restatement. The participant row gets its workout a minute later; this
 * hands it on to the post, guarded so it never claims a workout another feed
 * post of theirs already stands for.
 */
async function linkSessionPosts(
  userId: string | null,
  sessionId: string | null = null,
): Promise<void> {
  await db.query(
    `UPDATE posts p
        SET workout_id = bsp.workout_id
       FROM buddy_session_participants bsp
      WHERE p.buddy_session_id = bsp.session_id
        AND p.user_id = bsp.user_id
        AND p.workout_id IS NULL
        AND p.deleted_at IS NULL
        AND bsp.workout_id IS NOT NULL
        AND ($1::text IS NULL OR p.user_id = $1::text)
        AND ($2::text IS NULL OR bsp.session_id = $2::text)
        AND NOT EXISTS (
          SELECT 1 FROM posts q
           WHERE q.workout_id = bsp.workout_id AND q.user_id = p.user_id
             AND q.deleted_at IS NULL AND q.post_id <> p.post_id
             AND q.share_to_feed = p.share_to_feed)`,
    [userId, sessionId],
  );
}

/**
 * Does a buddy walk this user FINISHED today cover their goal?
 *
 * The posting gate reads the day's synced miles, and a walk that has just
 * ended is exactly the one that hasn't synced yet — so the person who walked
 * two miles with friends was told to "finish today's mile before you post".
 * The live participant row knows they did. Posting-gate only: nothing that
 * scores a streak reads this.
 */
export async function buddyWalkCreditsGoal(
  userId: string,
  localDate: string,
  goalMiles: number,
): Promise<boolean> {
  const rows = await db.query<{ ok: boolean }>(
    `SELECT EXISTS (
       SELECT 1 FROM buddy_session_participants bsp
         JOIN buddy_sessions s ON s.id = bsp.session_id
        WHERE bsp.user_id = $1
          AND bsp.status = 'finished'
          AND s.status IN ('active', 'completed')
          -- The host's day vs. the caller's: loose on the calendar, tight on
          -- the clock (same rule the posting window uses).
          AND s.local_date BETWEEN ($2::date - 1) AND ($2::date + 1)
          AND bsp.finished_at > NOW() - INTERVAL '30 hours'
          AND COALESCE(bsp.final_distance_miles, bsp.distance_miles, 0) + 1e-9
              >= $3::float * 0.95
     ) AS ok`,
    [userId, localDate, goalMiles],
  );
  return rows[0]?.ok === true;
}

// ─── Discovery helpers ──────────────────────────────────────────────────

/**
 * "This user is willing to be pulled into a buddy walk", as a SQL predicate.
 *
 * Everyone is opted IN by default, so the absence of a settings row must read
 * as yes — `notification_settings` is created lazily on first write, and most
 * users have never opened that screen. A plain join would silently hide every
 * one of them.
 *
 * Note this is the PREFERENCE, not the capability. `buddy_enrolled_at` answers
 * "can their app render this"; this answers "do they want it". Both are
 * required, and only this one belongs to the user.
 */
function buddyOptedInSql(userColumn: string): string {
  return `COALESCE(
    (SELECT ns.buddy_invites_enabled FROM notification_settings ns
      WHERE ns.user_id = ${userColumn}),
    TRUE
  )`;
}

/**
 * Filter a client-supplied invite list down to who may actually be invited.
 *
 * Every id here is client-asserted, so this re-checks the same four rules the
 * picker used rather than trusting that the list came from it: accepted
 * friendship, no block either way, a build that can render the invite, and the
 * invitee's own preference. Ineligible ids are dropped silently — telling a
 * host which of their friends opted out would leak a preference that isn't
 * theirs to see.
 *
 * Shared by createSession and the lobby's add-invitees path so the two cannot
 * drift; a second copy of these rules is exactly how a gate gets half-applied.
 *
 * ONE round trip regardless of how many people were picked. The first version
 * of this walked the list with three awaits each (friendship, blocks, then
 * enrollment + preference), so inviting three friends cost nine sequential
 * queries before the session row was even inserted — the single biggest reason
 * creating a walk felt slow. Set-based, the answer is the same and the cost is
 * flat. The ORDER of the returned ids follows the caller's list rather than the
 * table, so the host's picking order survives into the roster.
 */
async function eligibleInvitees(
  hostUserId: string,
  inviteIds: string[],
): Promise<string[]> {
  const wanted = inviteIds.filter((id) => id !== hostUserId);
  if (wanted.length === 0) return [];

  const rows = await db.query<{ user_id: string }>(
    `SELECT u.user_id
       FROM users u
       JOIN friendships f
         ON f.user_id = $1 AND f.friend_id = u.user_id AND f.status = 'accepted'
      WHERE u.user_id = ANY($2::text[])
        AND u.buddy_enrolled_at IS NOT NULL
        AND ${buddyOptedInSql("u.user_id")}
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $1 AND b.blocked_id = u.user_id)
              OR (b.blocker_id = u.user_id AND b.blocked_id = $1)
        )`,
    [hostUserId, wanted],
  );

  const allowed = new Set(rows.map((r) => r.user_id));
  return wanted.filter((id) => allowed.has(id));
}

/**
 * Friends eligible to be invited: accepted, unblocked both ways, on a build
 * that has the buddy screens, and not opted out.
 */
export async function getInviteCandidates(userId: string): Promise<
  Array<{
    user_id: string;
    username: string | null;
    first_name: string | null;
    last_name: string | null;
    profile_image_url: string | null;
    current_streak: number | null;
  }>
> {
  return db.query(
    `SELECT u.user_id, u.username, u.first_name, u.last_name,
            u.profile_image_url, u.current_streak
       FROM friendships f
       JOIN users u ON u.user_id = f.friend_id
      WHERE f.user_id = $1
        AND f.status = 'accepted'
        AND u.buddy_enrolled_at IS NOT NULL
        AND ${buddyOptedInSql("u.user_id")}
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $1 AND b.blocked_id = u.user_id)
              OR (b.blocker_id = u.user_id AND b.blocked_id = $1)
        )
      ORDER BY u.current_streak DESC NULLS LAST, u.username ASC`,
    [userId],
  );
}

/**
 * Friends who have a joinable buddy walk running right now.
 *
 * This is the deliberate substitute for ambient proximity sensing. Detecting
 * nearby friends in the background would need CoreBluetooth background
 * advertising: unreliable, battery-hungry, and a heavy privacy and App Review
 * surface. This gives the same "they're doing it, join them" moment with no new
 * permissions, at any distance, for both co-located and remote friends.
 *
 * PULL ONLY — there is deliberately no push here. Broadcasting "your friend
 * started walking" to every friend of every host is how a social feature turns
 * into spam, and buddy_invite already bypasses quiet hours. A friend who wants
 * you specifically can invite you directly.
 *
 * Sessions the caller is already in are excluded, as are full ones — an offer
 * to join something you cannot join is worse than no offer.
 *
 * A RUNNING walk stays joinable for as long as somebody is still in it, not for
 * the first twenty minutes. The old bound was reasoned from racing ("arriving
 * an hour deep means no chance of keeping up") but three of the four modes are
 * not races, and it made the common case impossible: you see a friend is out,
 * you put your shoes on, you walk down the road, and by the time you open the
 * app the offer has expired. Late is not the same as too late. A lobby is still
 * time-bounded by `created_at`, since the abandoned-lobby sweep cancels those
 * at three hours anyway and an older one is a room nobody is standing in.
 */
export async function getJoinableFriendSessions(userId: string): Promise<
  Array<{
    session_id: string;
    join_code: string;
    mode: string;
    activity_type: string;
    status: string;
    host_user_id: string;
    host_username: string | null;
    host_first_name: string | null;
    host_profile_image_url: string | null;
    participant_count: number;
    /** Walk straight in (host is a friend) vs. ask (a member is). */
    host_is_friend: boolean;
    /** 'requested' while an ask is pending, 'declined' once refused. */
    my_request_status: string | null;
    /** First names of the members the caller is friends with, up to three. */
    friend_first_names: string[];
  }>
> {
  // Rooms reachable only by ASKING are shown only to a build that can ask —
  // an older one draws a plain Join for every row and gets refused.
  const canRequest = await userSupports(
    userId,
    CLIENT_FEATURES.buddyJoinRequestV1,
  );
  return db.query(
    `SELECT s.id AS session_id, s.join_code, s.mode, s.activity_type, s.status,
            s.host_user_id, u.username AS host_username,
            u.first_name AS host_first_name,
            u.profile_image_url AS host_profile_image_url,
            (SELECT COUNT(*)::int FROM buddy_session_participants c
              WHERE c.session_id = s.id
                AND c.status IN ${OCCUPYING_STATUSES_SQL}) AS participant_count,
            EXISTS (
              SELECT 1 FROM friendships hf
               WHERE hf.user_id = $1 AND hf.friend_id = s.host_user_id
                 AND hf.status = 'accepted') AS host_is_friend,
            (SELECT CASE WHEN mine.status = 'requested' THEN 'requested'
                         WHEN mine.status = 'declined'
                              AND mine.requested_at IS NOT NULL THEN 'declined'
                    END
               FROM buddy_session_participants mine
              WHERE mine.session_id = s.id AND mine.user_id = $1) AS my_request_status,
            ARRAY(
              SELECT COALESCE(fu.first_name, fu.username, 'A friend')
                FROM buddy_session_participants fp
                JOIN users fu ON fu.user_id = fp.user_id
                JOIN friendships ff
                  ON ff.user_id = $1 AND ff.friend_id = fp.user_id
                 AND ff.status = 'accepted'
               WHERE fp.session_id = s.id
                 AND fp.status IN ('joined', 'ready', 'active', 'finished')
               ORDER BY fp.joined_at ASC NULLS LAST
               LIMIT 3
            )::text[] AS friend_first_names
       FROM buddy_sessions s
       JOIN users u ON u.user_id = s.host_user_id
      WHERE s.status IN ('lobby', 'active')
        -- Friends with the host (walk straight in), or — for a build that can
        -- ask — friends with somebody who is IN it.
        AND (
          EXISTS (
            SELECT 1 FROM friendships hf
             WHERE hf.user_id = $1 AND hf.friend_id = s.host_user_id
               AND hf.status = 'accepted')
          OR ($3::boolean AND EXISTS (
            SELECT 1 FROM buddy_session_participants fp
             JOIN friendships ff
               ON ff.user_id = $1 AND ff.friend_id = fp.user_id
              AND ff.status = 'accepted'
            WHERE fp.session_id = s.id
              AND fp.status IN ('joined', 'ready', 'active', 'finished')))
        )
        AND ${JOINABLE_WINDOW_SQL("s")}
        -- Already in it? Then it isn't an offer. A pending request is not
        -- "in" — the row stays so the client can say "Requested".
        AND NOT EXISTS (
          SELECT 1 FROM buddy_session_participants mine
           WHERE mine.session_id = s.id AND mine.user_id = $1
             AND mine.status NOT IN ('left', 'declined', 'requested')
        )
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $1 AND b.blocked_id = s.host_user_id)
              OR (b.blocker_id = s.host_user_id AND b.blocked_id = $1)
        )
        AND (SELECT COUNT(*) FROM buddy_session_participants c
              WHERE c.session_id = s.id
                AND c.status IN ${OCCUPYING_STATUSES_SQL}) < $2
      ORDER BY COALESCE(s.started_at, s.created_at) DESC
      LIMIT 5`,
    [userId, BUDDY_MAX_PARTICIPANTS, canRequest],
  );
}

/** The caller's live session (if any) plus any outstanding invites. */
export async function getMySessions(userId: string): Promise<{
  active: BuddySessionState | null;
  invites: BuddySessionState[];
}> {
  const rows = await db.query<{ session_id: string; status: string }>(
    `SELECT p.session_id, p.status
       FROM buddy_session_participants p
       JOIN buddy_sessions s ON s.id = p.session_id
      WHERE p.user_id = $1
        AND s.status IN ('lobby', 'active')
        AND p.status IN ('invited', 'joined', 'ready', 'active')
      -- The walk I'm actually IN outranks a lobby I'm waiting in, whichever
      -- was created later: two memberships (own booked lobby + a friend's
      -- walk joined mid-run) used to resolve to whichever row was newer.
      ORDER BY (p.status = 'active') DESC, (s.status = 'active') DESC,
               s.created_at DESC`,
    [userId],
  );

  let active: BuddySessionState | null = null;
  const invites: BuddySessionState[] = [];

  for (const row of rows) {
    const state = await getSessionState(row.session_id, userId);
    if (!state) continue;
    if (row.status === "invited") invites.push(state);
    else if (active === null) active = state;
  }

  return { active, invites };
}

export async function getRecap(
  sessionId: string,
  userId: string,
): Promise<{
  session: BuddySessionState;
  events: Array<{
    kind: string;
    user_id: string | null;
    payload: unknown;
    at: string;
  }>;
  /**
   * The feed post that already stands for this walk, if someone has made one.
   *
   * Additive, and load-bearing: "has this walk been shared" used to be
   * answered from a list in the poster's own UserDefaults, which by definition
   * cannot see what a friend did on their phone. So every participant's recap
   * lit its Post CTA, every participant posted, and one walk filled the feed
   * with N cards that each credited the others. With this the second person is
   * told the walk is already up and offered a slide on it instead.
   *
   * Null for old clients too — they simply ignore the field and keep their
   * device-local answer, which is no worse than what they ship with today.
   */
  post: BuddySessionPost | null;
}> {
  const membership = await participantStatus(sessionId, userId);
  if (membership === null) throw new BadRequestError("not_a_participant");

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");

  const events = await db.query<{
    kind: string;
    user_id: string | null;
    payload: unknown;
    at: string;
  }>(
    `SELECT kind, user_id, payload, at
       FROM buddy_session_events
      WHERE session_id = $1
      ORDER BY at ASC`,
    [sessionId],
  );

  return {
    session: await buildState(session),
    events,
    post: await buddySessionPost(sessionId, userId),
  };
}

// ─── Enrollment ─────────────────────────────────────────────────────────

/**
 * Stamp the caller as running a build that has the buddy UI.
 *
 * Idempotent — the guard keeps the original timestamp so this reads as "first
 * seen on a buddy-capable build", which is what makes it useful for measuring
 * adoption before flipping the env flag.
 */
export async function enrollUser(userId: string): Promise<void> {
  await db.query(
    `UPDATE users SET buddy_enrolled_at = NOW()
      WHERE user_id = $1 AND buddy_enrolled_at IS NULL`,
    [userId],
  );
}

// ─── Cron ───────────────────────────────────────────────────────────────

/**
 * Backstop sweep: finalize sessions whose clients all went away.
 *
 * Deliberately narrow. Live display staleness is computed at read time, so this
 * only has to catch the case where every participant's app died and nobody is
 * polling to trigger the lazy finalize.
 */
export async function sweepAbandonedSessions(): Promise<number> {
  const stale = await db.query<{ id: string }>(
    `SELECT s.id
       FROM buddy_sessions s
      WHERE s.status = 'active'
        AND COALESCE(s.started_at, s.created_at) < NOW() - ($1 || ' hours')::interval`,
    [String(BUDDY_ABANDON_HOURS)],
  );

  for (const row of stale) {
    try {
      // Someone who never reported a metre didn't walk — a promoted routine
      // nobody took used to be finalized as a real walk for everyone
      // (pushes, medals, history). They are released, not finished.
      await db.query(
        `UPDATE buddy_session_participants
            SET status = 'left'
          WHERE session_id = $1 AND status = 'active'
            AND last_progress_at IS NULL`,
        [row.id],
      );
      const walked = await db.query<{ n: number }>(
        `SELECT COUNT(*)::int AS n FROM buddy_session_participants
          WHERE session_id = $1 AND status IN ('active', 'finished')`,
        [row.id],
      );
      if (Number(walked[0]?.n ?? 0) === 0) {
        // Nobody moved: the walk never happened, so it never enters history.
        await cancelInternal(row.id, null, false);
        continue;
      }
      await db.query(
        `UPDATE buddy_session_participants
            SET status = 'finished', finished_at = COALESCE(finished_at, NOW())
          WHERE session_id = $1 AND status = 'active'`,
        [row.id],
      );
      await finalizeIfDue(row.id);
    } catch (err) {
      void logError("buddy", "failed to sweep abandoned buddy session", {
        context: { sessionId: row.id, error: String(err) },
      });
    }
  }

  // Lobbies nobody ever started are cancelled rather than left to accumulate
  // — UNSCHEDULED ones. A walk booked for Thursday is a lobby on purpose, and
  // this sweep used to cancel it three hours after booking, silently.
  const abandonedLobbies = await db.query<{ id: string }>(
    `SELECT id FROM buddy_sessions
      WHERE status = 'lobby'
        AND (
          (scheduled_start_at IS NULL
           AND created_at < NOW() - INTERVAL '3 hours')
          -- A scheduled walk nobody started within the promotion window
          -- (promoteDueScheduledSessions refuses one more than 30 minutes
          -- late) is over too.
          OR (scheduled_start_at IS NOT NULL
              AND scheduled_start_at < NOW() - INTERVAL '30 minutes')
        )`,
  );
  for (const row of abandonedLobbies) {
    try {
      await cancelInternal(row.id, null, false);
    } catch (err) {
      void logError("buddy", "failed to cancel abandoned buddy lobby", {
        context: { sessionId: row.id, error: String(err) },
      });
    }
  }

  return stale.length;
}

// ─── Shared history ─────────────────────────────────────────────────────

export interface BuddyPartner {
  user_id: string;
  username: string | null;
  first_name: string | null;
  profile_image_url: string | null;
  /** Walks the two of you both finished. */
  walks: number;
  /** YOUR miles across those walks — not the pooled total. */
  miles_together: number;
  /** `date` column, so a plain string is safe. */
  last_walk_date: string | null;
}

/**
 * Who you actually walk with, and how much.
 *
 * Nothing in the app recorded that two people have walked forty miles together
 * across twelve walks, which is the number that makes a shared habit feel like
 * a thing you HAVE rather than a thing you keep re-arranging. Derived entirely
 * from existing rows — no new writes, no counters to drift.
 *
 * Counts only sessions BOTH of you finished: a walk one person abandoned in the
 * lobby isn't a walk you took together, and counting it would inflate the one
 * number the feature is asking people to trust.
 *
 * The miles reported are the VIEWER's own, deliberately. A pooled total sounds
 * bigger but double-counts the same walk from each side, so the two of you
 * would see different numbers for the same history and neither would match the
 * distance either actually covered. `final_distance_miles` is the reconciled
 * figure stamped from the real synced workout; `distance_miles` is the live
 * display value and is only a fallback.
 *
 * Names are re-gated on the friendship still existing and no block either way —
 * you walked with them, but that doesn't entitle you to their profile forever.
 */
export async function getBuddyPartners(
  userId: string,
  limit = 10,
): Promise<BuddyPartner[]> {
  return db.query<BuddyPartner>(
    `SELECT u.user_id, u.username, u.first_name, u.profile_image_url,
            COUNT(*)::int AS walks,
            ROUND(SUM(COALESCE(me.final_distance_miles, me.distance_miles))::numeric, 2)::float
              AS miles_together,
            to_char(MAX(s.local_date), 'YYYY-MM-DD') AS last_walk_date
       FROM buddy_session_participants me
       JOIN buddy_sessions s ON s.id = me.session_id
       JOIN buddy_session_participants them
         ON them.session_id = me.session_id AND them.user_id <> me.user_id
       JOIN users u ON u.user_id = them.user_id
      WHERE me.user_id = $1
        AND me.status = 'finished'
        AND me.hidden_at IS NULL
        AND them.status = 'finished'
        AND s.status = 'completed'
        AND EXISTS (
          SELECT 1 FROM friendships f
           WHERE f.user_id = $1 AND f.friend_id = u.user_id
             AND f.status = 'accepted'
        )
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $1 AND b.blocked_id = u.user_id)
              OR (b.blocker_id = u.user_id AND b.blocked_id = $1)
        )
      GROUP BY u.user_id, u.username, u.first_name, u.profile_image_url
      ORDER BY miles_together DESC, walks DESC
      LIMIT $2`,
    [userId, Math.min(Math.max(limit, 1), 50)],
  );
}

// ─── History ────────────────────────────────────────────────────────────

/**
 * A walk only enters the archive once it's genuinely over AND was genuinely
 * shared: the session completed, the viewer finished it, and at least one other
 * person finished it too. A room the viewer opened and walked alone is a solo
 * walk that happened to have a lobby — it belongs to the workout history, not
 * to "walks together", and listing it would make the shared-miles number the
 * screen leads with mean two different things at once.
 *
 * `$1` is the viewer; `friendParam` is the optional friend filter, passed in
 * because the two callers number their parameters differently. The friend
 * filter and the someone-else-was-there requirement are the SAME clause on
 * purpose: filtering to a friend must still mean "a walk we finished
 * together", not "a walk of mine they were invited to".
 */
const historyHasCompanionSql = (friendParam: string) => `EXISTS (
  SELECT 1 FROM buddy_session_participants o
   WHERE o.session_id = s.id
     AND o.user_id <> $1
     AND o.status = 'finished'
     AND (${friendParam}::text IS NULL OR o.user_id = ${friendParam})
     AND NOT EXISTS (
       SELECT 1 FROM user_blocks b
        WHERE (b.blocker_id = $1 AND b.blocked_id = o.user_id)
           OR (b.blocker_id = o.user_id AND b.blocked_id = $1)
     )
)`;

/** Ordering key. `ended_at` is stamped at close; `created_at` is the backstop
 * for any historical row that closed before it was being written. */
const HISTORY_SORT_KEY = `COALESCE(s.ended_at, s.created_at)`;

interface HistorySessionRow {
  id: string;
  mode: BuddyMode;
  activity_type: string;
  goal_value: number | null;
  local_date: string;
  started_at: string | null;
  ended_at: string | null;
  winner_user_id: string | null;
  group_distance_miles: number;
  my_distance_miles: number;
  my_duration_seconds: number;
  my_place: number | null;
  cursor: string;
}

/**
 * Past buddy walks, newest first — the archive behind the history screen.
 *
 * Keyset paginated on `ended_at` (URL-safe ISO, same shape as the feed's
 * cursor: a raw `timestamptz::text` carries a '+' that Express decodes as a
 * space and the next page's cast 500s).
 *
 * Roster identity is re-gated per read, exactly as getBuddyPartners re-gates
 * its names: a blocked participant is dropped from the roster entirely, and an
 * un-friended one comes back with a null name so the client can draw them
 * anonymously. Neither changes `group_distance_miles`, which stays what the
 * recap said on the day — an archive that quietly restates a past walk's
 * numbers because a friendship ended is worse than one that doesn't.
 */
export async function getBuddyHistory(
  userId: string,
  options: { limit?: number; before?: string | null; friendId?: string | null },
): Promise<{ sessions: BuddyHistoryEntry[]; next_before: string | null }> {
  const limit = Math.min(Math.max(options.limit ?? 20, 1), 40);
  const before = options.before ?? null;
  const friendId = options.friendId ?? null;

  const rows = await db.query<HistorySessionRow>(
    `SELECT s.id, s.mode, s.activity_type, s.goal_value, s.winner_user_id,
            to_char(s.local_date, 'YYYY-MM-DD') AS local_date,
            s.started_at, s.ended_at,
            ROUND(COALESCE(me.final_distance_miles, me.distance_miles)::numeric, 3)::float
              AS my_distance_miles,
            me.duration_seconds AS my_duration_seconds,
            me.place AS my_place,
            (SELECT ROUND(
                      COALESCE(SUM(COALESCE(o.final_distance_miles, o.distance_miles)), 0)::numeric,
                      3)::float
               FROM buddy_session_participants o
              WHERE o.session_id = s.id AND o.status = 'finished'
            ) AS group_distance_miles,
            to_char(${HISTORY_SORT_KEY} AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS.US') || 'Z' AS cursor
       FROM buddy_session_participants me
       JOIN buddy_sessions s ON s.id = me.session_id
      WHERE me.user_id = $1
        AND me.status = 'finished'
        AND me.hidden_at IS NULL
        AND ($2::timestamptz IS NULL OR ${HISTORY_SORT_KEY} < $2::timestamptz)
        AND s.status = 'completed'
        AND ${historyHasCompanionSql("$4")}
      ORDER BY ${HISTORY_SORT_KEY} DESC
      LIMIT $3`,
    [userId, before, limit, friendId],
  );

  if (rows.length === 0) return { sessions: [], next_before: null };

  const sessionIds = rows.map((r) => r.id);
  const [participants, photos, postIds] = await Promise.all([
    loadHistoryParticipants(userId, sessionIds),
    buddySessionPhotos(userId, sessionIds),
    buddySessionPostIds(userId, sessionIds),
  ]);

  const bySession = new Map<string, BuddyHistoryParticipant[]>();
  for (const p of participants) {
    const list = bySession.get(p.session_id) ?? [];
    list.push({
      user_id: p.user_id,
      username: p.username,
      first_name: p.first_name,
      profile_image_url: p.profile_image_url,
      distance_miles: Number(p.distance_miles) || 0,
      duration_seconds: Number(p.duration_seconds) || 0,
      place: p.place,
      is_host: p.is_host === true,
      workout_id: p.workout_id ?? null,
      final_distance_miles:
        p.final_distance_miles === null || p.final_distance_miles === undefined
          ? null
          : Number(p.final_distance_miles),
      has_route: p.has_route === true,
    });
    bySession.set(p.session_id, list);
  }

  const photosBySession = new Map<string, BuddyHistoryEntry["photos"]>();
  for (const photo of photos) {
    const list = photosBySession.get(photo.buddy_session_id) ?? [];
    list.push({
      post_id: photo.post_id,
      user_id: photo.user_id,
      media_url: photo.media_url,
      caption: photo.caption,
      is_crew: photo.is_crew === true,
    });
    photosBySession.set(photo.buddy_session_id, list);
  }

  const sessions: BuddyHistoryEntry[] = rows.map((row) => ({
    id: row.id,
    mode: row.mode,
    activity_type: row.activity_type,
    goal_value: row.goal_value === null ? null : Number(row.goal_value),
    local_date: row.local_date,
    started_at: row.started_at,
    ended_at: row.ended_at,
    winner_user_id: row.winner_user_id,
    group_distance_miles: Number(row.group_distance_miles) || 0,
    my_distance_miles: Number(row.my_distance_miles) || 0,
    my_duration_seconds: Number(row.my_duration_seconds) || 0,
    my_place: row.my_place,
    participants: bySession.get(row.id) ?? [],
    photos: photosBySession.get(row.id) ?? [],
    post_id: postIds.get(row.id) ?? null,
    cursor: row.cursor,
  }));

  // Only advertise another page when this one was full — a short page is the
  // end of the archive, and handing back a cursor there makes the client spend
  // a round trip to learn nothing.
  const next_before =
    rows.length === limit ? (rows[rows.length - 1]?.cursor ?? null) : null;

  return { sessions, next_before };
}

interface HistoryParticipantRow extends BuddyHistoryParticipant {
  session_id: string;
}

async function loadHistoryParticipants(
  viewerId: string,
  sessionIds: string[],
): Promise<HistoryParticipantRow[]> {
  return db.query<HistoryParticipantRow>(
    `SELECT p.session_id, p.user_id,
            ROUND(COALESCE(p.final_distance_miles, p.distance_miles)::numeric, 3)::float
              AS distance_miles,
            p.duration_seconds, p.place,
            (p.user_id = s.host_user_id) AS is_host,
            p.workout_id,
            ROUND(p.final_distance_miles::numeric, 3)::float AS final_distance_miles,
            -- A trace exists AND the owner shares maps (the viewer's own always
            -- counts). A stealth walk has no workout_routes row, so it reads
            -- exactly like maps-off here — the rule every route read keeps.
            (p.workout_id IS NOT NULL
              AND EXISTS (SELECT 1 FROM workout_routes wr WHERE wr.workout_id = p.workout_id)
              AND (p.user_id = $1 OR COALESCE(
                    (SELECT ns.share_route_maps FROM notification_settings ns
                      WHERE ns.user_id = p.user_id), TRUE))) AS has_route,
            CASE WHEN vis.ok THEN u.username END AS username,
            CASE WHEN vis.ok THEN u.first_name END AS first_name,
            CASE WHEN vis.ok THEN u.profile_image_url END AS profile_image_url
       FROM buddy_session_participants p
       JOIN buddy_sessions s ON s.id = p.session_id
       JOIN users u ON u.user_id = p.user_id
       CROSS JOIN LATERAL (
         SELECT (p.user_id = $1 OR EXISTS (
                   SELECT 1 FROM friendships f
                    WHERE f.user_id = $1 AND f.friend_id = p.user_id
                      AND f.status = 'accepted'
                 )) AS ok
       ) vis
      WHERE p.session_id = ANY($2::text[])
        AND p.status = 'finished'
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $1 AND b.blocked_id = p.user_id)
              OR (b.blocker_id = p.user_id AND b.blocked_id = $1)
        )
      ORDER BY p.session_id,
               COALESCE(p.final_distance_miles, p.distance_miles) DESC`,
    [viewerId, sessionIds],
  );
}

/**
 * Lifetime totals across the same set of walks the history lists — one query
 * rather than counting the page, so the headline doesn't grow as you scroll.
 *
 * Scoped to the same friend filter when one is applied, so "you and Sam" reads
 * consistently between the headline and the list under it.
 */
export async function getBuddyHistoryTotals(
  userId: string,
  friendId?: string | null,
): Promise<BuddyHistoryTotals> {
  const rows = await db.query<{
    walks: number;
    miles: number;
    partners: number;
    first_walk_date: string | null;
    last_walk_date: string | null;
  }>(
    `WITH mine AS (
       SELECT s.id, s.local_date,
              COALESCE(me.final_distance_miles, me.distance_miles) AS miles
         FROM buddy_session_participants me
         JOIN buddy_sessions s ON s.id = me.session_id
        WHERE me.user_id = $1
          AND me.status = 'finished'
          AND me.hidden_at IS NULL
          AND s.status = 'completed'
          AND ${historyHasCompanionSql("$2")}
     )
     SELECT COUNT(*)::int AS walks,
            ROUND(COALESCE(SUM(miles), 0)::numeric, 2)::float AS miles,
            (SELECT COUNT(DISTINCT o.user_id)::int
               FROM buddy_session_participants o
              WHERE o.session_id IN (SELECT id FROM mine)
                AND o.user_id <> $1
                AND o.status = 'finished') AS partners,
            to_char(MIN(local_date), 'YYYY-MM-DD') AS first_walk_date,
            to_char(MAX(local_date), 'YYYY-MM-DD') AS last_walk_date
       FROM mine`,
    [userId, friendId ?? null],
  );

  const row = rows[0];
  return {
    walks: Number(row?.walks) || 0,
    miles: Number(row?.miles) || 0,
    partners: Number(row?.partners) || 0,
    first_walk_date: row?.first_walk_date ?? null,
    last_walk_date: row?.last_walk_date ?? null,
  };
}

/**
 * Take a walk out of the caller's own archive — or put it back.
 *
 * Buddy walks get started by accident: a mis-tap on a friend's Join card, a
 * routine that fired on a day nobody went out, a room opened to check what the
 * screen looked like. Those land in "Walks Together" forever, next to the walks
 * that meant something, and skew the one number the whole screen asks people to
 * trust.
 *
 * PER VIEWER, and a soft hide. A walk is a shared event: erasing the row would
 * silently rewrite somebody else's history and their partner totals, which is
 * not a thing one participant may do to another. So this stamps the CALLER's
 * own participant row and every history read filters on it — their archive
 * loses the walk, everyone else's is untouched, and nothing is destroyed, so
 * un-hiding is the same call with `hidden: false`.
 *
 * Only a walk that is genuinely over. A live session is exited with leave or
 * cancel, and hiding one from the archive it hasn't reached yet would read as
 * having quit it while the roster still showed you walking.
 */
export async function setBuddyWalkHidden(
  userId: string,
  sessionId: string,
  hidden: boolean,
): Promise<void> {
  const updated = await db.query<{ session_id: string }>(
    `UPDATE buddy_session_participants p
        SET hidden_at = CASE WHEN $3 THEN NOW() ELSE NULL END
       FROM buddy_sessions s
      WHERE p.session_id = $1
        AND p.user_id = $2
        AND s.id = p.session_id
        AND s.status IN ('completed', 'cancelled')
      RETURNING p.session_id`,
    [sessionId, userId, hidden],
  );
  if (updated.length === 0) {
    // Either not theirs to hide or not finished yet. One code for both: which
    // it is would tell a caller whether a session id they guessed exists.
    throw new BadRequestError("walk_not_hideable");
  }
}
