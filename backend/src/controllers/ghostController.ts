import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  getFriendGhosts,
  GHOST_ACTIVITIES,
  GhostActivity,
} from "../services/ghostService.js";

/**
 * GET /ghosts/friends?activity=running|walking
 *
 * Friends whose fastest mile can be raced, fastest first. Self-scoped on
 * `req.userId`, so no `requireSelfAccess` — there is no id in the path to
 * mismatch.
 */
export async function friendGhosts(req: AuthenticatedRequest, res: Response) {
  try {
    const raw = String(req.query.activity ?? "running");
    // Whitelisted like buddyController does for mode/activityType: an
    // unvalidated value would reach the query as a workout_type filter and
    // silently return nothing rather than telling the client it asked wrong.
    if (!GHOST_ACTIVITIES.includes(raw as GhostActivity)) {
      return res.status(400).json({ error: "invalid_activity" });
    }
    const ghosts = await getFriendGhosts(req.userId!, raw as GhostActivity);
    return res.status(200).json({ ghosts });
  } catch (error: any) {
    console.error("Error loading friend ghosts:", error.message);
    return res.status(500).json({ error: "Error loading friend ghosts" });
  }
}
