import { PostgresService } from "./DbService.js";
import {
  sendLiveActivityPush,
  type LiveActivityPush,
} from "./pushNotificationService.js";
import { logError } from "./errorLogService.js";
import { BadRequestError } from "../errors/Errors.js";

const db = PostgresService.getInstance();

/**
 * The buddy walk's lock-screen countdown (iOS Live Activity).
 *
 * The root cause behind "my buddy's phone didn't track": a guest's tracker
 * starts only when their lobby is on screen as the countdown ends, and a
 * phone pocketed after tapping Ready shows nothing at all when the host
 * starts. The app now starts a Live Activity from the lobby ("Waiting for Rob
 * to start") and reports its ActivityKit push token here. When the host
 * starts, the SERVER pushes the countdown straight onto the lock screen (an
 * alerting update, so the screen lights), then "It's started — tap to start
 * recording" if they still haven't opened it, then ends the card the moment
 * their phone starts reporting.
 *
 * Phases, which the app's `BuddyWalkActivityAttributes.ContentState` mirrors:
 *   waiting   — in the lobby, the host hasn't started (set by the app)
 *   countdown — started, `starts_at_unix` is the shared start (server)
 *   started   — the start passed and this phone isn't recording (server)
 *   ended     — the card is going away (with an `end` event)
 *
 * Content-state keys are camelCase because they are decoded by the app's
 * Codable as-is: `phase`, `startsAtUnix`, `crewCount`.
 */
export type BuddyActivityPhase = "waiting" | "countdown" | "started" | "ended";

/** How long a countdown/started card may sit before iOS greys it out. */
const STALE_AFTER_SECONDS = 2 * 60 * 60;

function contentState(
  phase: BuddyActivityPhase,
  startsAtUnix: number | null,
  crewCount: number,
): Record<string, unknown> {
  const state: Record<string, unknown> = { phase, crewCount };
  if (startsAtUnix !== null) state.startsAtUnix = startsAtUnix;
  return state;
}

/**
 * Store (or replace) a walker's Live Activity token. Only someone ON the
 * walk — invited/joined/ready/active — can register; anything else is
 * `not_a_participant`, so a token can never be attached to a stranger's walk.
 */
export async function registerLiveActivity(
  sessionId: string,
  userId: string,
  pushToken: string,
  environment: string | null | undefined,
): Promise<void> {
  const token = String(pushToken ?? "").trim();
  if (!/^[0-9a-fA-F]{16,512}$/.test(token)) {
    throw new BadRequestError("invalid_push_token");
  }
  const env = environment === "production" ? "production" : "sandbox";
  const rows = await db.query<{ ok: number }>(
    `INSERT INTO buddy_live_activities (session_id, user_id, push_token, environment)
     SELECT $1::varchar, $2::text, $3::text, $4::text
      WHERE EXISTS (
        SELECT 1 FROM buddy_session_participants p
          JOIN buddy_sessions s ON s.id = p.session_id
         WHERE p.session_id = $1 AND p.user_id = $2
           AND p.status IN ('invited', 'joined', 'ready', 'active')
           AND s.status IN ('lobby', 'active')
      )
     ON CONFLICT (session_id, user_id)
       DO UPDATE SET push_token = EXCLUDED.push_token,
                     environment = EXCLUDED.environment,
                     created_at = NOW()
     RETURNING 1 AS ok`,
    [sessionId, userId, token.toLowerCase(), env],
  );
  if (rows.length === 0) throw new BadRequestError("not_a_participant");
}

async function deleteDead(sessionId: string, userId: string, token: string) {
  await db.query(
    `DELETE FROM buddy_live_activities
      WHERE session_id = $1 AND user_id = $2 AND push_token = $3`,
    [sessionId, userId, token],
  );
}

async function crewCount(sessionId: string): Promise<number> {
  const rows = await db.query<{ n: number }>(
    `SELECT COUNT(*)::int AS n FROM buddy_session_participants
      WHERE session_id = $1 AND status IN ('joined', 'ready', 'active', 'finished')`,
    [sessionId],
  );
  return Number(rows[0]?.n ?? 0);
}

async function pushTo(
  rows: {
    session_id: string;
    user_id: string;
    push_token: string;
    environment: string;
  }[],
  push: LiveActivityPush,
): Promise<number> {
  let ok = 0;
  for (const row of rows) {
    const result = await sendLiveActivityPush(
      row.push_token,
      push,
      row.environment,
    );
    if (result === "ok") ok += 1;
    if (result === "dead")
      await deleteDead(row.session_id, row.user_id, row.push_token);
  }
  return ok;
}

/**
 * The host started (or "Start now" pulled the start in): put the countdown on
 * every registered lock screen except the person who tapped it, who is
 * looking at the countdown already. Alerting, so a pocketed phone lights up.
 * Never throws.
 */
export async function pushCountdownToActivities(
  sessionId: string,
  actorUserId: string | null,
): Promise<number> {
  try {
    const session = await db.query<{ starts: number | null }>(
      `SELECT EXTRACT(EPOCH FROM started_at)::float8 AS starts
         FROM buddy_sessions WHERE id = $1 AND status = 'active'`,
      [sessionId],
    );
    const starts = session[0]?.starts;
    if (starts === null || starts === undefined) return 0;
    const rows = await db.query<{
      session_id: string;
      user_id: string;
      push_token: string;
      environment: string;
    }>(
      `SELECT a.session_id, a.user_id, a.push_token, a.environment
         FROM buddy_live_activities a
         JOIN buddy_session_participants p
           ON p.session_id = a.session_id AND p.user_id = a.user_id
        WHERE a.session_id = $1
          AND p.status = 'active' AND p.last_progress_at IS NULL
          AND ($2::text IS NULL OR a.user_id <> $2)`,
      [sessionId, actorUserId],
    );
    if (rows.length === 0) return 0;
    const n = await crewCount(sessionId);
    const now = Math.floor(Date.now() / 1000);
    return await pushTo(rows, {
      event: "update",
      contentState: contentState(
        Number(starts) <= now ? "started" : "countdown",
        Number(starts),
        n,
      ),
      alert: {
        title: "Your buddy walk is starting",
        body: "Tap to start recording with everyone.",
      },
      staleDate: now + STALE_AFTER_SECONDS,
    });
  } catch (err) {
    void logError("buddy", "failed to push buddy countdown live activities", {
      context: { sessionId, error: String(err) },
    });
    return 0;
  }
}

/**
 * The walk started and THIS walker's phone still isn't recording: flip their
 * card to "It's started — tap to start recording". Quiet (no alert): the
 * not-recording push (`alertSilentWalkers`) is the alert. Never throws.
 */
export async function pushStartedToActivity(
  sessionId: string,
  userId: string,
): Promise<boolean> {
  try {
    const rows = await db.query<{
      session_id: string;
      user_id: string;
      push_token: string;
      environment: string;
      starts: number | null;
    }>(
      `SELECT a.session_id, a.user_id, a.push_token, a.environment,
              EXTRACT(EPOCH FROM s.started_at)::float8 AS starts
         FROM buddy_live_activities a
         JOIN buddy_sessions s ON s.id = a.session_id
        WHERE a.session_id = $1 AND a.user_id = $2 AND s.status = 'active'`,
      [sessionId, userId],
    );
    if (rows.length === 0) return false;
    const n = await crewCount(sessionId);
    const now = Math.floor(Date.now() / 1000);
    return (
      (await pushTo(rows, {
        event: "update",
        contentState: contentState(
          "started",
          rows[0].starts === null ? null : Number(rows[0].starts),
          n,
        ),
        staleDate: now + STALE_AFTER_SECONDS,
      })) > 0
    );
  } catch (err) {
    void logError("buddy", "failed to push buddy started live activity", {
      context: { sessionId, userId, error: String(err) },
    });
    return false;
  }
}

/**
 * Take the card down: this walker started recording (the workout's own Live
 * Activity takes over), finished, left, or the walk closed. Omit `userId` to
 * end everyone's. Deletes the rows first so a second call does nothing.
 * Never throws.
 */
export async function endLiveActivities(
  sessionId: string,
  userId?: string,
): Promise<number> {
  try {
    const rows = await db.query<{
      session_id: string;
      user_id: string;
      push_token: string;
      environment: string;
    }>(
      `DELETE FROM buddy_live_activities
        WHERE session_id = $1 AND ($2::text IS NULL OR user_id = $2)
        RETURNING session_id, user_id, push_token, environment`,
      [sessionId, userId ?? null],
    );
    if (rows.length === 0) return 0;
    const now = Math.floor(Date.now() / 1000);
    return await pushTo(rows, {
      event: "end",
      contentState: contentState("ended", null, 0),
      dismissalDate: now,
    });
  } catch (err) {
    void logError("buddy", "failed to end buddy live activities", {
      context: { sessionId, userId, error: String(err) },
    });
    return 0;
  }
}
