import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import hasRequiredKeys from "../utils/hasRequiredKeys.js";
import {
  getWeeklyChallengeForUser,
  getWeeklyHistory,
} from "../services/weeklyChallengeService.js";

/**
 * This week's challenge, the user's progress, and their friends' standings.
 *
 * Self-only (`requireSelfAccess` on the route): the payload includes the
 * viewer's own circle, which is not another user's to read.
 */
export async function getWeeklyChallenge(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  try {
    const payload = await getWeeklyChallengeForUser(req.params.userId);
    if (!payload) {
      // No active catalog — the feature is effectively off rather than broken,
      // so say so plainly instead of 500ing.
      return res.status(404).json({ error: "No weekly challenge available" });
    }
    return res.status(200).json(payload);
  } catch (error: any) {
    console.error("Error getting weekly challenge:", error.message);
    return res
      .status(500)
      .json({ error: "Error getting weekly challenge: " + error.message });
  }
}

export async function getWeeklyChallengeHistory(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  try {
    const limit = req.query.limit
      ? parseInt(req.query.limit as string, 10)
      : 26;
    const history = await getWeeklyHistory(
      req.params.userId,
      Number.isFinite(limit) ? limit : 26,
    );
    return res.status(200).json({ history });
  } catch (error: any) {
    console.error("Error getting weekly challenge history:", error.message);
    return res.status(500).json({
      error: "Error getting weekly challenge history: " + error.message,
    });
  }
}
