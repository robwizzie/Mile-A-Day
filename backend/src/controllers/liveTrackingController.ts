import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  startSession,
  heartbeat,
  endSession,
} from "../services/liveTrackingService.js";

/**
 * Live tracking presence endpoints. All self-scoped via req.userId (no
 * :userId params, so requireSelfAccess doesn't apply) — a device can only
 * ever start/beat/end ITS user's session.
 */

export async function startLiveTracking(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const result = await startSession(req.userId!, req.body?.workout_type);
    return res.status(200).json(result);
  } catch (error: any) {
    console.error("Error starting live tracking session:", error.message);
    res.status(500).json({ error: "Error starting live tracking session" });
  }
}

export async function liveTrackingHeartbeat(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const sessionId = req.body?.session_id;
    if (typeof sessionId !== "string" || sessionId.length === 0) {
      return res.status(400).json({ error: "session_id is required" });
    }

    const result = await heartbeat(req.userId!, sessionId);
    if (result === null) {
      // Stale/ended session (e.g. a second device rotated session_id, or a
      // zombie heartbeat after end). Client treats this as "re-start or
      // stop", never as an error loop.
      return res
        .status(404)
        .json({ error: "No active session", code: "no_active_session" });
    }
    return res.status(200).json(result);
  } catch (error: any) {
    console.error("Error on live tracking heartbeat:", error.message);
    res.status(500).json({ error: "Error on live tracking heartbeat" });
  }
}

export async function endLiveTracking(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const sessionId = req.body?.session_id;
    if (typeof sessionId !== "string" || sessionId.length === 0) {
      return res.status(400).json({ error: "session_id is required" });
    }
    await endSession(req.userId!, sessionId);
    return res.status(200).json({ ended: true });
  } catch (error: any) {
    console.error("Error ending live tracking session:", error.message);
    res.status(500).json({ error: "Error ending live tracking session" });
  }
}
