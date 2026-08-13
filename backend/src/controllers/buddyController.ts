import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { BadRequestError } from "../errors/Errors.js";
import { buddySessionsEnabled } from "../services/buddyFeatures.js";
import {
  BUDDY_ACTIVITY_TYPES,
  BUDDY_LOCATION_TYPES,
  BUDDY_MODES,
  BUDDY_ORIGINS,
  type BuddyActivityType,
  type BuddyLocationType,
  type BuddyMode,
  type BuddyOrigin,
} from "../types/buddy.js";
import {
  cancelSession,
  createSession,
  declineSession,
  enrollUser,
  finishParticipation,
  getBuddyHistory,
  getBuddyHistoryTotals,
  getInviteCandidates,
  getJoinableFriendSessions,
  getMySessions,
  getRecap,
  getSessionState,
  joinSession,
  leaveSession,
  recordProgress,
  setBuddyWalkHidden,
  setParticipantLocationType,
  setReady,
  getBuddyPartners,
  startSession,
  updateSession,
} from "../services/buddySessionService.js";
import {
  createRecurringWalk,
  deleteRecurringWalk,
  listRecurringWalks,
  updateRecurringWalk,
} from "../services/buddyRecurringService.js";
import {
  lockUnearnedPhotos,
  type ViewerGoalGate,
} from "../services/postService.js";
import { getDailyGoalStatus } from "../services/workoutService.js";
import { signMediaUrlsDeep } from "../services/mediaSigningService.js";

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

/**
 * The viewer's mile status, used to gate today's photos. Mirrors the copy in
 * postsController — fail-OPEN, so a stats hiccup briefly over-shows rather than
 * blanking every photo on the screen.
 */
async function viewerPhotoGate(userId: string): Promise<ViewerGoalGate> {
  try {
    const goal = await getDailyGoalStatus(userId);
    return { completed: goal.completed, localDate: goal.localDate };
  } catch (error) {
    console.error("[buddy viewerPhotoGate] goal status failed:", error);
    return { completed: true, localDate: "" };
  }
}

/** Sentinel for "the client sent a scheduled start we won't accept". */
const INVALID_SCHEDULE = Symbol("invalid_scheduled_start");

/**
 * Validate an optional scheduled-start timestamp.
 *
 * A scheduled walk has to be far enough out to be worth scheduling and near
 * enough to still be real — rejecting here keeps a typo'd year from parking a
 * lobby in the table forever.
 *
 * Returns `undefined` for absent (leave alone) and `null` for an explicit clear
 * — the lobby needs to tell those apart, since "don't touch my schedule" and
 * "cancel my schedule" are different requests. A rejection comes back as the
 * sentinel rather than a throw so both callers map it to the same 400.
 */
function parseScheduledStart(
  raw: unknown,
): string | null | undefined | typeof INVALID_SCHEDULE {
  if (raw === undefined) return undefined;
  if (raw === null) return null;
  const when = new Date(String(raw));
  if (Number.isNaN(when.getTime())) return INVALID_SCHEDULE;
  const minutesOut = (when.getTime() - Date.now()) / 60000;
  if (minutesOut < 2 || minutesOut > 60 * 24 * 14) return INVALID_SCHEDULE;
  return when.toISOString();
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
    const scheduledStartAt = req.body?.scheduledStartAt;

    if (!BUDDY_MODES.includes(mode as BuddyMode)) {
      return res.status(400).json({ error: "invalid_mode" });
    }
    if (!BUDDY_ACTIVITY_TYPES.includes(activityType as BuddyActivityType)) {
      return res.status(400).json({ error: "invalid_activity_type" });
    }
    if (inviteUserIds !== undefined && !Array.isArray(inviteUserIds)) {
      return res.status(400).json({ error: "invalid_invite_list" });
    }
    // Absent is fine (the service defaults to 'invite'), but a PRESENT value
    // has to be one we know — otherwise it reaches the table's CHECK and
    // surfaces as a 500 instead of a 400.
    if (
      origin !== undefined &&
      !BUDDY_ORIGINS.includes(origin as BuddyOrigin)
    ) {
      return res.status(400).json({ error: "invalid_origin" });
    }

    const scheduled = parseScheduledStart(scheduledStartAt);
    if (scheduled === INVALID_SCHEDULE) {
      return res.status(400).json({ error: "invalid_scheduled_start" });
    }

    const state = await createSession(req.userId!, {
      mode: mode as BuddyMode,
      goalValue: goalValue === undefined ? null : Number(goalValue),
      activityType: activityType as BuddyActivityType,
      inviteUserIds: inviteUserIds as string[] | undefined,
      origin: origin as BuddyOrigin | undefined,
      scheduledStartAt: scheduled,
    });
    res.status(201).json(state);
  } catch (error) {
    handleError(res, error, "creating buddy session");
  }
}

/**
 * PATCH /buddy/sessions/:sessionId — host edits the lobby before it starts.
 *
 * Every enum is whitelisted before it reaches the service for the same reason
 * `createSessionController` does it: an unvalidated value lands on the table's
 * CHECK constraint and surfaces as a 500 instead of a 400.
 */
export async function updateSessionController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const { mode, goalValue, activityType, inviteUserIds } = req.body ?? {};

    if (mode !== undefined && !BUDDY_MODES.includes(mode as BuddyMode)) {
      return res.status(400).json({ error: "invalid_mode" });
    }
    if (
      activityType !== undefined &&
      !BUDDY_ACTIVITY_TYPES.includes(activityType as BuddyActivityType)
    ) {
      return res.status(400).json({ error: "invalid_activity_type" });
    }
    if (inviteUserIds !== undefined && !Array.isArray(inviteUserIds)) {
      return res.status(400).json({ error: "invalid_invite_list" });
    }

    const scheduled = parseScheduledStart(req.body?.scheduledStartAt);
    if (scheduled === INVALID_SCHEDULE) {
      return res.status(400).json({ error: "invalid_scheduled_start" });
    }

    const state = await updateSession(req.params.sessionId, req.userId!, {
      mode: mode as BuddyMode | undefined,
      // Absent leaves the stored goal alone; an explicit null clears it. Both
      // matter, so this cannot collapse to `?? null`.
      goalValue:
        goalValue === undefined
          ? undefined
          : goalValue === null
            ? null
            : Number(goalValue),
      activityType: activityType as BuddyActivityType | undefined,
      scheduledStartAt: scheduled,
      inviteUserIds: inviteUserIds as string[] | undefined,
    });
    res.json(state);
  } catch (error) {
    handleError(res, error, "updating buddy session");
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

/**
 * An unrecognized `locationType` is a 400, never a silent drop: it decides
 * which sensor the phone measures with, so quietly falling back to outdoor
 * would hand a treadmill walker a GPS that cannot see them.
 */
const INVALID_LOCATION = Symbol("invalid_location_type");

function parseLocationType(
  raw: unknown,
): BuddyLocationType | undefined | typeof INVALID_LOCATION {
  if (raw === undefined || raw === null) return undefined;
  if (BUDDY_LOCATION_TYPES.includes(raw as BuddyLocationType)) {
    return raw as BuddyLocationType;
  }
  return INVALID_LOCATION;
}

export async function joinSessionController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const code =
      typeof req.query.code === "string" ? req.query.code : req.body?.code;
    const locationType = parseLocationType(req.body?.locationType);
    if (locationType === INVALID_LOCATION) {
      return res.status(400).json({ error: "invalid_location_type" });
    }
    res.json(
      await joinSession(req.userId!, {
        sessionId: req.params.sessionId,
        code,
        locationType,
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
    const locationType = parseLocationType(req.body?.locationType);
    if (locationType === INVALID_LOCATION) {
      return res.status(400).json({ error: "invalid_location_type" });
    }
    res.json(await joinSession(req.userId!, { code, locationType }));
  } catch (error) {
    handleError(res, error, "joining buddy session by code");
  }
}

/**
 * PATCH /buddy/sessions/:sessionId/me — this participant's own settings.
 *
 * Participant-scoped, not host-scoped: everything here describes one person,
 * so unlike the lobby PATCH beside it there is no `not_host` and no lobby-only
 * restriction. Membership is checked in the service.
 */
export async function updateParticipantController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const locationType = parseLocationType(req.body?.locationType);
    if (locationType === INVALID_LOCATION) {
      return res.status(400).json({ error: "invalid_location_type" });
    }
    if (locationType === undefined) {
      return res.status(400).json({ error: "nothing_to_update" });
    }
    res.json(
      await setParticipantLocationType(
        req.params.sessionId,
        req.userId!,
        locationType,
      ),
    );
  } catch (error) {
    handleError(res, error, "updating buddy participant");
  }
}

/** POST /buddy/sessions/:sessionId/cancel — host calls the walk off. */
export async function cancelSessionController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    res.json(await cancelSession(req.params.sessionId, req.userId!));
  } catch (error) {
    handleError(res, error, "cancelling buddy session");
  }
}

/**
 * DELETE /buddy/history/:sessionId — take a finished walk out of MY archive.
 *
 * A hide, not a delete, and scoped to the caller's own participant row: the
 * walk is a shared event and erasing it would rewrite the other people's
 * history too. `?hidden=false` puts it back.
 */
export async function deleteHistoryEntryController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const hidden = req.query.hidden !== "false" && req.body?.hidden !== false;
    await setBuddyWalkHidden(req.userId!, req.params.sessionId, hidden);
    res.json({ ok: true, hidden });
  } catch (error) {
    handleError(res, error, "hiding buddy walk");
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

// ─── Recurring walks ────────────────────────────────────────────────────

/** GET /buddy/recurring — this user's standing walks. */
export async function listRoutinesController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    res.json({ routines: await listRecurringWalks(req.userId!) });
  } catch (error) {
    handleError(res, error, "loading buddy routines");
  }
}

/**
 * POST /buddy/recurring — make a walk a habit.
 *
 * Enum whitelisting mirrors createSessionController; everything else
 * (days, time, timezone, goal) is validated in the service so the PATCH
 * shares exactly one copy of those rules.
 */
export async function createRoutineController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const { mode, goalValue, activityType, inviteUserIds } = req.body ?? {};
    if (!BUDDY_MODES.includes(mode as BuddyMode)) {
      return res.status(400).json({ error: "invalid_mode" });
    }
    if (!BUDDY_ACTIVITY_TYPES.includes(activityType as BuddyActivityType)) {
      return res.status(400).json({ error: "invalid_activity_type" });
    }
    if (inviteUserIds !== undefined && !Array.isArray(inviteUserIds)) {
      return res.status(400).json({ error: "invalid_invite_list" });
    }
    const routine = await createRecurringWalk(req.userId!, {
      mode: mode as BuddyMode,
      goalValue: goalValue === undefined ? null : Number(goalValue),
      activityType: activityType as BuddyActivityType,
      inviteUserIds: inviteUserIds as string[] | undefined,
      daysOfWeek: req.body?.daysOfWeek,
      minutesOfDay: req.body?.minutesOfDay,
      timezone: req.body?.timezone,
    });
    res.status(201).json(routine);
  } catch (error) {
    handleError(res, error, "creating buddy routine");
  }
}

/** PATCH /buddy/recurring/:routineId — including the on/off switch. */
export async function updateRoutineController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const { mode, goalValue, activityType, inviteUserIds, isActive } =
      req.body ?? {};
    if (mode !== undefined && !BUDDY_MODES.includes(mode as BuddyMode)) {
      return res.status(400).json({ error: "invalid_mode" });
    }
    if (
      activityType !== undefined &&
      !BUDDY_ACTIVITY_TYPES.includes(activityType as BuddyActivityType)
    ) {
      return res.status(400).json({ error: "invalid_activity_type" });
    }
    if (inviteUserIds !== undefined && !Array.isArray(inviteUserIds)) {
      return res.status(400).json({ error: "invalid_invite_list" });
    }
    const routine = await updateRecurringWalk(
      req.userId!,
      req.params.routineId,
      {
        mode: mode as BuddyMode | undefined,
        goalValue:
          goalValue === undefined
            ? undefined
            : goalValue === null
              ? null
              : Number(goalValue),
        activityType: activityType as BuddyActivityType | undefined,
        inviteUserIds: inviteUserIds as string[] | undefined,
        daysOfWeek: req.body?.daysOfWeek,
        minutesOfDay: req.body?.minutesOfDay,
        timezone: req.body?.timezone,
        isActive: isActive === undefined ? undefined : Boolean(isActive),
      },
    );
    res.json(routine);
  } catch (error) {
    handleError(res, error, "updating buddy routine");
  }
}

/** DELETE /buddy/recurring/:routineId */
export async function deleteRoutineController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    await deleteRecurringWalk(req.userId!, req.params.routineId);
    res.json({ ok: true });
  } catch (error) {
    handleError(res, error, "deleting buddy routine");
  }
}

/**
 * GET /buddy/partners — who you actually walk with, and how much.
 *
 * Self-scoped on the token: your own walking history is yours.
 */
export async function partnersController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    res.json({ partners: await getBuddyPartners(req.userId!) });
  } catch (error) {
    handleError(res, error, "loading buddy partners");
  }
}

/**
 * GET /buddy/history?limit&before&friendId — the walks you've already taken.
 *
 * Self-scoped on the token. `before` is the `cursor` from the last entry of the
 * previous page (or `next_before`), never a hand-built timestamp — it is
 * emitted in the URL-safe ISO form the feed uses, because a raw
 * `timestamptz::text` carries a '+' that Express decodes as a space.
 *
 * Totals ride along with the FIRST page only: they describe the whole archive,
 * not the page, so re-sending them while paginating is pure weight.
 *
 * Media urls are signed here, like every other endpoint that returns one — the
 * DB stores bare paths.
 */
export async function historyController(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!requireEnabled(res)) return;
  try {
    const rawLimit = Number(req.query.limit);
    const before =
      typeof req.query.before === "string" && req.query.before.length > 0
        ? req.query.before
        : null;
    const friendId =
      typeof req.query.friendId === "string" && req.query.friendId.length > 0
        ? req.query.friendId
        : null;

    const { sessions, next_before } = await getBuddyHistory(req.userId!, {
      limit: Number.isFinite(rawLimit) ? rawLimit : undefined,
      before,
      friendId,
    });

    // A photo taken TODAY by someone else is still behind the app-wide
    // "finish your mile to see today's photos" gate — the history screen is
    // not a way around it. lockUnearnedPhotos keys on the poster and the
    // post's local_date, so every older walk passes through untouched. A
    // withheld photo is DROPPED here rather than shipped blank: the feed draws
    // a deliberate locked card in its place, and there is nothing to draw a
    // lock on in a history thumbnail strip.
    const gate = await viewerPhotoGate(req.userId!);
    for (const session of sessions) {
      const gated = lockUnearnedPhotos(
        session.photos.map((photo) => ({
          ...photo,
          local_date: session.local_date,
          is_auto: false,
        })),
        req.userId!,
        gate,
      );
      session.photos = gated
        .filter((photo) => !!photo.media_url)
        .map(({ post_id, user_id, media_url, caption }) => ({
          post_id,
          user_id,
          media_url: media_url ?? "",
          caption,
        }));
    }

    res.json(
      signMediaUrlsDeep({
        sessions,
        next_before,
        // Absent on later pages; the client keeps what page 1 gave it.
        totals: before
          ? undefined
          : await getBuddyHistoryTotals(req.userId!, friendId),
      }),
    );
  } catch (error) {
    handleError(res, error, "loading buddy history");
  }
}
