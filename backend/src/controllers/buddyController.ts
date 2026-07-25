import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { BadRequestError } from "../errors/Errors.js";
import { buddySessionsEnabled } from "../services/buddyFeatures.js";
import {
  BUDDY_ACTIVITY_TYPES,
  BUDDY_MODES,
  type BuddyActivityType,
  type BuddyMode,
} from "../types/buddy.js";
import {
  createSession,
  declineSession,
  enrollUser,
  finishParticipation,
  getInviteCandidates,
  getJoinableFriendSessions,
  getMySessions,
  getRecap,
  getSessionState,
  joinSession,
  leaveSession,
  recordProgress,
  setReady,
  startSession,
} from "../services/buddySessionService.js";

/**
 * Buddy Walks & Runs controllers.
 *
 * Every handler is gated on `buddySessionsEnabled()` and 404s when off, so an
 * older client that somehow probes these paths sees "no such route" rather than
 * a half-working feature.
 */

function requireEnabled(res: Response): boolean {
  if (!buddySessionsEnabled()) {
    res.status(404).json({ error: "not_found" });
    return false;
  }
  return true;
}

/**
 * Map a service-level BadRequestError to a 400 carrying its code, and anything
 * else to a generic 500 — never leak raw error text (matches the global handler
 * in server.ts).
 */
function handleError(res: Response, error: unknown, logLabel: string): void {
  if (error instanceof BadRequestError) {
    res.status(400).json({ error: error.message });
    return;
  }
  console.error(`Error ${logLabel}:`, error);
  res.status(500).json({ error: `Error ${logLabel}` });
}

export async function enrollController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    await enrollUser(req.userId!);
    res.json({ ok: true });
  } catch (error) {
    handleError(res, error, "enrolling in buddy sessions");
  }
}

export async function inviteCandidatesController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    res.json({ candidates: await getInviteCandidates(req.userId!) });
  } catch (error) {
    handleError(res, error, "loading buddy invite candidates");
  }
}

export async function joinableFriendSessionsController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    res.json({ sessions: await getJoinableFriendSessions(req.userId!) });
  } catch (error) {
    handleError(res, error, "loading joinable friend sessions");
  }
}

export async function createSessionController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const { mode, goalValue, activityType, inviteUserIds, origin } =
      req.body ?? {};

    if (!BUDDY_MODES.includes(mode as BuddyMode)) {
      return res.status(400).json({ error: "invalid_mode" });
    }
    if (!BUDDY_ACTIVITY_TYPES.includes(activityType as BuddyActivityType)) {
      return res.status(400).json({ error: "invalid_activity_type" });
    }
    if (inviteUserIds !== undefined && !Array.isArray(inviteUserIds)) {
      return res.status(400).json({ error: "invalid_invite_list" });
    }

    const state = await createSession(req.userId!, {
      mode: mode as BuddyMode,
      goalValue: goalValue === undefined ? null : Number(goalValue),
      activityType: activityType as BuddyActivityType,
      inviteUserIds: inviteUserIds as string[] | undefined,
      origin,
    });
    res.status(201).json(state);
  } catch (error) {
    handleError(res, error, "creating buddy session");
  }
}

export async function mySessionsController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    res.json(await getMySessions(req.userId!));
  } catch (error) {
    handleError(res, error, "loading buddy sessions");
  }
}

/**
 * The polling endpoint. A null state means the caller's `since` cursor already
 * matches the stored version — answered with 304 so the client can skip
 * decoding entirely.
 */
export async function sessionStateController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const rawSince = req.query.since;
    const since =
      typeof rawSince === "string" && rawSince !== ""
        ? Number(rawSince)
        : undefined;

    const state = await getSessionState(
      req.params.sessionId,
      req.userId!,
      Number.isFinite(since) ? since : undefined,
    );
    if (state === null) return res.status(304).end();
    res.json(state);
  } catch (error) {
    handleError(res, error, "loading buddy session state");
  }
}

export async function joinSessionController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const code =
      typeof req.query.code === "string" ? req.query.code : req.body?.code;
    res.json(
      await joinSession(req.userId!, {
        sessionId: req.params.sessionId,
        code,
      }),
    );
  } catch (error) {
    handleError(res, error, "joining buddy session");
  }
}

/** Join purely by code, with no session id in the path (deep-link entry). */
export async function joinByCodeController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const code =
      typeof req.query.code === "string" ? req.query.code : req.body?.code;
    if (!code) return res.status(400).json({ error: "code_required" });
    res.json(await joinSession(req.userId!, { code }));
  } catch (error) {
    handleError(res, error, "joining buddy session by code");
  }
}

export async function declineSessionController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    await declineSession(req.params.sessionId, req.userId!);
    res.json({ ok: true });
  } catch (error) {
    handleError(res, error, "declining buddy session");
  }
}

export async function leaveSessionController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    await leaveSession(req.params.sessionId, req.userId!);
    res.json({ ok: true });
  } catch (error) {
    handleError(res, error, "leaving buddy session");
  }
}

export async function readyController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const ready = req.body?.ready !== false;
    res.json(await setReady(req.params.sessionId, req.userId!, ready));
  } catch (error) {
    handleError(res, error, "setting buddy ready state");
  }
}

export async function startSessionController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    res.json(await startSession(req.params.sessionId, req.userId!));
  } catch (error) {
    handleError(res, error, "starting buddy session");
  }
}

/**
 * Progress report. Responds with the FULL session snapshot, not an ack — while
 * tracking, this is the client's only call, so folding the roster read into the
 * write halves round trips and removes poll-vs-post ordering races.
 */
export async function progressController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const { distanceMiles, durationSeconds } = req.body ?? {};
    if (distanceMiles === undefined || durationSeconds === undefined) {
      return res.status(400).json({ error: "progress_required" });
    }
    res.json(
      await recordProgress(
        req.params.sessionId,
        req.userId!,
        Number(distanceMiles),
        Number(durationSeconds),
      ),
    );
  } catch (error) {
    handleError(res, error, "recording buddy progress");
  }
}

export async function finishController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    res.json(await finishParticipation(req.params.sessionId, req.userId!));
  } catch (error) {
    handleError(res, error, "finishing buddy session");
  }
}

export async function recapController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    res.json(await getRecap(req.params.sessionId, req.userId!));
  } catch (error) {
    handleError(res, error, "loading buddy recap");
  }
}
