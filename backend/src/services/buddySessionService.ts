import { PostgresService } from "./DbService.js";
import { areFriends } from "./friendshipService.js";
import { sendPush } from "./pushNotificationService.js";
import { shouldSendNotification } from "./notificationSettingsService.js";
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
  type BuddyMode,
  type BuddyParticipantView,
  type BuddySessionRow,
  type BuddySessionState,
} from "../types/buddy.js";

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
  }>(
    // Staleness means "was reporting, then stopped" — NOT "hasn't reported
    // yet". A participant's first progress report is up to 5s out, so falling
    // back to the session start keeps the whole roster from rendering as
    // out-of-range for the first moments of every walk.
    `SELECT p.user_id, u.username, u.first_name, u.last_name, u.profile_image_url,
            p.status, p.distance_miles, p.duration_seconds, p.place,
            p.final_distance_miles,
            (p.status = 'active'
             AND COALESCE(p.last_progress_at, s.started_at, NOW())
                   < NOW() - ($2 || ' seconds')::interval
            ) AS is_stale
       FROM buddy_session_participants p
       JOIN users u ON u.user_id = p.user_id
       JOIN buddy_sessions s ON s.id = p.session_id
      WHERE p.session_id = $1
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
    is_host: r.user_id === hostUserId,
    place: r.place,
    final_distance_miles:
      r.final_distance_miles === null ? null : Number(r.final_distance_miles),
  }));
}

function toState(
  session: BuddySessionRow,
  participants: BuddyParticipantView[],
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
    started_at: session.started_at,
    ends_at: session.ends_at,
    ended_at: session.ended_at,
    winner_user_id: session.winner_user_id,
    state_version: session.state_version,
    participants,
    group_distance_miles: Math.round(groupDistance * 1000) / 1000,
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

  const participants = await loadParticipants(sessionId, session.host_user_id);
  return toState(session, participants);
}

// ─── Create ─────────────────────────────────────────────────────────────

export interface CreateSessionInput {
  mode: BuddyMode;
  goalValue?: number | null;
  activityType: BuddyActivityType;
  inviteUserIds?: string[];
  origin?: "invite" | "code" | "join_active" | "nearby";
}

export async function createSession(
  hostUserId: string,
  input: CreateSessionInput,
): Promise<BuddySessionState> {
  const { mode, activityType } = input;

  // A goal is required for every mode except 'together', which is goal-less by
  // definition. Validating here keeps the CHECK constraints from having to
  // encode cross-column rules.
  const needsGoal = mode !== "together";
  const goalValue = input.goalValue ?? null;
  if (needsGoal && (goalValue === null || !(goalValue > 0))) {
    throw new BadRequestError("goal_required");
  }
  if (mode === "race_time" && goalValue !== null && goalValue > 24 * 60) {
    throw new BadRequestError("goal_too_large");
  }
  if (
    (mode === "coop_goal" || mode === "race_goal") &&
    goalValue !== null &&
    goalValue > 200
  ) {
    throw new BadRequestError("goal_too_large");
  }

  const inviteIds = Array.from(new Set(input.inviteUserIds ?? [])).filter(
    (id) => id !== hostUserId,
  );
  if (inviteIds.length + 1 > BUDDY_MAX_PARTICIPANTS) {
    throw new BadRequestError("too_many_participants");
  }

  // Every invitee must be an accepted friend, unblocked in both directions, AND
  // enrolled (i.e. running a build that has the buddy UI). An unenrolled
  // invitee would get a push for a screen that does not exist in their app.
  const eligible: string[] = [];
  for (const inviteeId of inviteIds) {
    if (!(await areFriends(hostUserId, inviteeId))) continue;
    if (await isBlockedEitherWay(hostUserId, inviteeId)) continue;
    const enrolled = await db.query(
      `SELECT 1 FROM users WHERE user_id = $1 AND buddy_enrolled_at IS NOT NULL`,
      [inviteeId],
    );
    if (enrolled.length === 0) continue;
    eligible.push(inviteeId);
  }

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
            origin, local_date)
         VALUES ($1, $2, $3, $4, $5, 'lobby', $6,
                 ((NOW() AT TIME ZONE 'America/New_York')::date))
         RETURNING id`,
        [
          joinCode,
          hostUserId,
          mode,
          goalValue,
          activityType,
          input.origin ?? "invite",
        ],
      );
      sessionId = inserted[0]?.id ?? null;
    } catch (err: any) {
      if (err?.code !== "23505") throw err;
    }
  }
  if (!sessionId) throw new BadRequestError("could_not_allocate_code");

  // Host is 'joined' immediately — they never see their own invite.
  await db.query(
    `INSERT INTO buddy_session_participants (session_id, user_id, status, joined_at)
     VALUES ($1, $2, 'joined', NOW())`,
    [sessionId, hostUserId],
  );

  for (const inviteeId of eligible) {
    await db.query(
      `INSERT INTO buddy_session_participants
         (session_id, user_id, status, invited_by)
       VALUES ($1, $2, 'invited', $3)
       ON CONFLICT (session_id, user_id) DO NOTHING`,
      [sessionId, inviteeId, hostUserId],
    );
  }

  await recordEvent(sessionId, hostUserId, "created", { mode, goalValue });
  void notifyInvitees(sessionId, hostUserId, eligible);

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  return toState(session, await loadParticipants(sessionId, hostUserId));
}

async function notifyInvitees(
  sessionId: string,
  hostUserId: string,
  inviteeIds: string[],
): Promise<void> {
  if (inviteeIds.length === 0) return;
  try {
    const hostRows = await db.query<{
      first_name: string | null;
      username: string | null;
    }>(`SELECT first_name, username FROM users WHERE user_id = $1`, [
      hostUserId,
    ]);
    const hostName =
      hostRows[0]?.first_name || hostRows[0]?.username || "A friend";

    for (const inviteeId of inviteeIds) {
      if (!(await shouldSendNotification(inviteeId, hostUserId, "buddy"))) {
        continue;
      }
      await sendPush(inviteeId, {
        title: "Buddy Walk",
        body: `${hostName} wants to walk with you — starting now`,
        type: "buddy_invite",
        category: "BUDDY_INVITE",
        data: { session_id: sessionId, host_user_id: hostUserId },
      });
    }
  } catch (err) {
    void logError("buddy", "failed to notify buddy invitees", {
      userId: hostUserId,
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
 */
export async function joinSession(
  userId: string,
  opts: { sessionId?: string; code?: string },
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
    const invited = await participantStatus(sessionId, userId);
    if (invited === null) {
      if (!(await areFriends(session.host_user_id, userId))) {
        throw new BadRequestError("not_friends_with_host");
      }
    }
    if (await isBlockedEitherWay(session.host_user_id, userId)) {
      throw new BadRequestError("blocked");
    }
  }

  const client = await db.getClient();
  try {
    await client.query("BEGIN");
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [
      `buddy_session:${sessionId}`,
    ]);

    const already = await client.query<{ status: string }>(
      `SELECT status FROM buddy_session_participants
        WHERE session_id = $1 AND user_id = $2`,
      [sessionId, userId],
    );
    const previous = already.rows[0]?.status ?? null;

    // Only count people occupying a slot. 'left'/'declined' free theirs.
    if (previous === null || previous === "left" || previous === "declined") {
      const countRows = await client.query<{ n: string }>(
        `SELECT COUNT(*)::text AS n FROM buddy_session_participants
          WHERE session_id = $1
            AND status NOT IN ('left', 'declined')`,
        [sessionId],
      );
      if (Number(countRows.rows[0]?.n ?? 0) >= BUDDY_MAX_PARTICIPANTS) {
        await client.query("ROLLBACK");
        throw new BadRequestError("session_full");
      }
    }

    await client.query(
      `INSERT INTO buddy_session_participants (session_id, user_id, status, joined_at)
       VALUES ($1, $2, 'joined', NOW())
       ON CONFLICT (session_id, user_id) DO UPDATE
         SET status = 'joined', joined_at = COALESCE(buddy_session_participants.joined_at, NOW())
         WHERE buddy_session_participants.status IN ('invited', 'left', 'declined')`,
      [sessionId, userId],
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

  const fresh = await getSessionRow(sessionId);
  if (!fresh) throw new BadRequestError("session_not_found");
  return toState(fresh, await loadParticipants(sessionId, fresh.host_user_id));
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
  return toState(
    session,
    await loadParticipants(sessionId, session.host_user_id),
  );
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

  const started = await db.query<{ id: string; started_at: string }>(
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
      RETURNING id, started_at`,
    [sessionId, String(BUDDY_START_COUNTDOWN_SECONDS)],
  );

  if (started.length > 0) {
    // Everyone still in the lobby becomes active. Invitees who never responded
    // are left behind rather than dragged in.
    await db.query(
      `UPDATE buddy_session_participants
          SET status = 'active'
        WHERE session_id = $1 AND status IN ('joined', 'ready')`,
      [sessionId],
    );
    await recordEvent(sessionId, userId, "started");
    void notifySessionStarted(sessionId, userId);
  }

  const fresh = await getSessionRow(sessionId);
  if (!fresh) throw new BadRequestError("session_not_found");
  return toState(fresh, await loadParticipants(sessionId, fresh.host_user_id));
}

async function notifySessionStarted(
  sessionId: string,
  hostUserId: string,
): Promise<void> {
  try {
    const rows = await db.query<{ user_id: string }>(
      `SELECT user_id FROM buddy_session_participants
        WHERE session_id = $1 AND status = 'active' AND user_id <> $2`,
      [sessionId, hostUserId],
    );
    for (const row of rows) {
      if (!(await shouldSendNotification(row.user_id, hostUserId, "buddy"))) {
        continue;
      }
      await sendPush(row.user_id, {
        title: "Buddy Walk started",
        body: "Your buddy walk is underway — get moving!",
        type: "buddy_started",
        data: { session_id: sessionId },
      });
    }
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
): Promise<BuddySessionState> {
  if (!Number.isFinite(distanceMiles) || distanceMiles < 0) {
    throw new BadRequestError("invalid_distance");
  }
  if (!Number.isFinite(durationSeconds) || durationSeconds < 0) {
    throw new BadRequestError("invalid_duration");
  }

  const status = await participantStatus(sessionId, userId);
  if (status === null) throw new BadRequestError("not_a_participant");
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
    ],
  );

  await bumpVersion(sessionId);
  await finalizeIfDue(sessionId);

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  return toState(
    session,
    await loadParticipants(sessionId, session.host_user_id),
  );
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
  await bumpVersion(sessionId);
  await recordEvent(sessionId, userId, "finished");
  await finalizeIfDue(sessionId);

  const session = await getSessionRow(sessionId);
  if (!session) throw new BadRequestError("session_not_found");
  return toState(
    session,
    await loadParticipants(sessionId, session.host_user_id),
  );
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
export async function finalizeIfDue(sessionId: string): Promise<void> {
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
    await closeSession(sessionId, null);
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

  await closeSession(sessionId, winnerId);
}

async function closeSession(
  sessionId: string,
  winnerId: string | null,
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

  await recordEvent(sessionId, winnerId, "completed", { winnerId });
  void notifySessionFinished(sessionId);

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

async function notifySessionFinished(sessionId: string): Promise<void> {
  try {
    const rows = await db.query<{ user_id: string }>(
      `SELECT user_id FROM buddy_session_participants
        WHERE session_id = $1 AND status = 'finished'`,
      [sessionId],
    );
    for (const row of rows) {
      await sendPush(row.user_id, {
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
    await db.query(
      `UPDATE buddy_session_participants p
          SET workout_id = w.workout_id,
              final_distance_miles = w.distance
         FROM buddy_sessions s, workouts w
        WHERE p.session_id = s.id
          AND p.user_id = $1
          AND p.workout_id IS NULL
          AND p.status = 'finished'
          AND s.status = 'completed'
          AND s.ended_at > NOW() - INTERVAL '12 hours'
          AND w.workout_id = ANY($2::varchar[])
          AND w.user_id = $1
          AND w.deleted_at IS NULL
          AND w.exclusion_reason IS NULL
          AND w.device_end_date >= s.started_at
          AND (w.device_end_date - (w.total_duration || ' seconds')::interval)
                <= COALESCE(s.ended_at, NOW()) + INTERVAL '10 minutes'`,
      [userId, uploadedWorkoutIds],
    );

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

// ─── Discovery helpers ──────────────────────────────────────────────────

/** Friends eligible to be invited: accepted, unblocked both ways, enrolled. */
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
  }>
> {
  return db.query(
    `SELECT s.id AS session_id, s.join_code, s.mode, s.activity_type, s.status,
            s.host_user_id, u.username AS host_username,
            u.first_name AS host_first_name,
            u.profile_image_url AS host_profile_image_url,
            (SELECT COUNT(*)::int FROM buddy_session_participants c
              WHERE c.session_id = s.id
                AND c.status NOT IN ('left', 'declined')) AS participant_count
       FROM buddy_sessions s
       JOIN users u ON u.user_id = s.host_user_id
       JOIN friendships f
         ON f.user_id = $1 AND f.friend_id = s.host_user_id
        AND f.status = 'accepted'
      WHERE s.status IN ('lobby', 'active')
        -- Only just-started walks. Offering to join a session an hour deep
        -- means arriving with no chance of keeping up.
        AND COALESCE(s.started_at, s.created_at) > NOW() - INTERVAL '20 minutes'
        AND NOT EXISTS (
          SELECT 1 FROM buddy_session_participants mine
           WHERE mine.session_id = s.id AND mine.user_id = $1
             AND mine.status NOT IN ('left', 'declined')
        )
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $1 AND b.blocked_id = s.host_user_id)
              OR (b.blocker_id = s.host_user_id AND b.blocked_id = $1)
        )
        AND (SELECT COUNT(*) FROM buddy_session_participants c
              WHERE c.session_id = s.id
                AND c.status NOT IN ('left', 'declined')) < $2
      ORDER BY COALESCE(s.started_at, s.created_at) DESC
      LIMIT 5`,
    [userId, BUDDY_MAX_PARTICIPANTS],
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
      ORDER BY s.created_at DESC`,
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
    session: toState(
      session,
      await loadParticipants(sessionId, session.host_user_id),
    ),
    events,
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

  // Lobbies nobody ever started are cancelled rather than left to accumulate.
  await db.query(
    `UPDATE buddy_sessions
        SET status = 'cancelled', ended_at = NOW(),
            state_version = state_version + 1
      WHERE status = 'lobby'
        AND created_at < NOW() - INTERVAL '3 hours'`,
  );

  return stale.length;
}
