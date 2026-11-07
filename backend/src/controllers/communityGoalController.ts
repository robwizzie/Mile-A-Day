import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import hasRequiredKeys from "../utils/hasRequiredKeys.js";
import { getCommunityGoalForUser } from "../services/communityGoalService.js";

/** The shared goal and the caller's own part in it. `goal` is null between goals. */
export async function getCommunityGoal(req: AuthenticatedRequest, res: Response) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  try {
    return res.status(200).json(await getCommunityGoalForUser(req.params.userId));
  } catch (error: any) {
    console.error("Error getting community goal:", error.message);
    return res.status(500).json({ error: "Failed to load community goal" });
  }
}
