import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  enrollStreakFeatures,
  getStreakFeaturesPayload,
  getAssistableFriends,
  giveStreakAssist,
} from "../services/streakFeatureService.js";
import {
  streakFeaturesGloballyEnabled,
  coverageActiveFor,
} from "../services/streakFeatureCore.js";
import { getActiveStreak } from "../services/workoutService.js";

/**
 * POST /users/streak-features/enable — idempotent enrollment stamp. Only the
 * new app build calls this (once, on launch, fire-and-forget), which is what
 * keeps every streak feature invisible to older builds: without the stamp the
 * server omits all token fields and never runs token side-effects.
 */
export async function enableStreakFeaturesController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const result = await enrollStreakFeatures(req.userId!);
    res.status(200).json(result);
  } catch (error: any) {
    console.error("Error enabling streak features:", error.message);
    res.status(500).json({ error: "Error enabling streak features" });
  }
}

/**
 * GET /users/streak-features/status — the caller's meters, coverage, natural
 * flag, plus friends they could currently rescue. `active:false` (and nothing
 * else) until the env switch is on AND the caller enrolled.
 */
export async function streakFeaturesStatusController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const userId = req.userId!;
    if (!(await coverageActiveFor(userId))) {
      return res.status(200).json({ active: false });
    }
    const { streak, start } = await getActiveStreak(userId);
    const payload = await getStreakFeaturesPayload(userId, streak, start);
    if (!payload) return res.status(200).json({ active: false });

    // Only surface rescuable friends to a caller actually holding an Assist —
    // the friends-page CTA is meaningless (and noisy) otherwise.
    const assistableFriends = payload.streak_assist.held
      ? await getAssistableFriends(userId)
      : [];

    res.status(200).json({
      active: true,
      streak,
      ...payload,
      assistable_friends: assistableFriends,
    });
  } catch (error: any) {
    console.error("Error getting streak-features status:", error.message);
    res.status(500).json({ error: "Error getting streak features" });
  }
}

/**
 * POST /users/streak-features/assist/:friendId — spend a held Streak Assist
 * to restore the friend's just-broken streak. Status strings map 1:1 to HTTP
 * so the client can show a precise reason.
 */
export async function giveStreakAssistController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!streakFeaturesGloballyEnabled()) {
      return res.status(403).json({ error: "not_available" });
    }
    const result = await giveStreakAssist(req.userId!, req.params.friendId);
    switch (result.status) {
      case "ok":
        return res
          .status(200)
          .json({ ok: true, restored_streak: result.restored_streak });
      case "already_saved":
        return res.status(409).json({ error: "already_saved" });
      case "no_token":
        return res.status(409).json({ error: "no_token" });
      case "no_recent_break":
      case "window_passed":
      case "gap_too_wide":
        return res.status(409).json({ error: result.status });
      case "disabled":
      case "not_enrolled":
      case "friend_not_enrolled":
      case "forbidden":
        return res.status(403).json({ error: result.status });
    }
  } catch (error: any) {
    console.error("Error giving streak assist:", error.message);
    res.status(500).json({ error: "Error giving streak assist" });
  }
}
