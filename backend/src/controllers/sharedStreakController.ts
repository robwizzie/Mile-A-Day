import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { getSharedStreaks } from "../services/sharedStreakService.js";

/**
 * Batch "friend streaks" for the authenticated viewer against a set of friend
 * ids. New endpoint (no existing behavior touched) that only the feature build
 * calls — older App Store clients never hit it, so the live app is unaffected.
 */
export async function getSharedStreaksBatch(
  req: AuthenticatedRequest,
  res: Response,
) {
  const viewerId = req.userId!;
  const friendIds = req.body?.friend_ids;

  if (!Array.isArray(friendIds) || friendIds.length === 0) {
    return res
      .status(400)
      .json({ error: "friend_ids must be a non-empty array" });
  }

  // Bound the batch and drop non-strings so a crafted request can't balloon the
  // query.
  const ids = friendIds
    .filter((x: unknown): x is string => typeof x === "string")
    .slice(0, 200);

  try {
    const shared = await getSharedStreaks(viewerId, ids);
    res.status(200).json({ shared_streaks: shared });
  } catch (error: any) {
    console.error("Error computing shared streaks:", error.message);
    res.status(500).json({ error: "Error computing shared streaks" });
  }
}
