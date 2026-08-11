import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  enrollStreakFeatures,
  getStreakFeaturesPayload,
  getAssistableFriends,
  getFriendRescueStatus,
  getDonationBudget,
  getPendingAssistOffers,
  offerStreakAssist,
  requestStreakAssist,
  respondToAssistOffer,
  AssistExchangeResult,
} from "../services/streakFeatureService.js";
import { getStreakFeatureRow } from "../services/streakFeatureCore.js";
import { getUserLocalToday } from "../services/workoutService.js";
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

    const row = await getStreakFeatureRow(userId);
    const userToday = await getUserLocalToday(userId);

    // Donating no longer costs the caller a token, so the list is no longer
    // gated on holding one — it's gated on the FRIEND holding one (inside
    // getAssistableFriends). The caller's spare miles decide whether the CTA
    // is live or locked, which the client renders from donation_budget.
    const [assistableFriends, donationBudget, pendingOffers] = await Promise.all(
      [
        getAssistableFriends(userId),
        getDonationBudget(userId, row!, userToday),
        getPendingAssistOffers(userId),
      ],
    );

    res.status(200).json({
      active: true,
      streak,
      ...payload,
      assistable_friends: assistableFriends,
      donation_budget: donationBudget,
      pending_offers: pendingOffers,
    });
  } catch (error: any) {
    console.error("Error getting streak-features status:", error.message);
    res.status(500).json({ error: "Error getting streak features" });
  }
}

/**
 * GET /users/streak-features/rescue/:friendId — can the caller save THIS
 * friend's streak right now, how many days would it come back as, and if not,
 * why not. One friend, one read: the profile needs this even when the caller
 * isn't holding an Assist (so the CTA can show the meter instead of silently
 * rendering nothing, which is indistinguishable from "the feature is broken").
 */
export async function friendRescueStatusController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const status = await getFriendRescueStatus(
      req.userId!,
      req.params.friendId,
    );
    res.status(200).json(status);
  } catch (error: any) {
    console.error("Error getting friend rescue status:", error.message);
    res.status(500).json({ error: "Error getting rescue status" });
  }
}

/**
 * Status strings map 1:1 to HTTP so the client can show a precise reason:
 * 403 is "you may not", 409 is "not right now".
 */
function sendExchangeResult(res: Response, result: AssistExchangeResult) {
  switch (result.status) {
    case "ok":
      return res.status(200).json({
        ok: true,
        offer_id: result.offer_id,
        target_date: result.target_date,
        restored_streak: result.restored_streak,
        applied: result.applied,
      });
    case "no_token":
    case "friend_no_token":
    case "no_miles":
    case "no_savable_day":
    case "window_passed":
    case "gap_too_wide":
    case "already_saved":
    case "already_pending":
      return res.status(409).json({ error: result.status });
    case "not_found":
      return res.status(404).json({ error: result.status });
    case "disabled":
    case "not_enrolled":
    case "friend_not_enrolled":
    case "forbidden":
      return res.status(403).json({ error: result.status });
  }
}

/**
 * POST /users/streak-features/assist/:friendId — donate one of today's miles
 * past goal to a friend holding an Assist. Creates a PENDING offer: the token
 * that pays for the coverage is theirs, so they get the last word.
 */
export async function giveStreakAssistController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!streakFeaturesGloballyEnabled()) {
      return res.status(403).json({ error: "not_available" });
    }
    const result = await offerStreakAssist(req.userId!, req.params.friendId);
    return sendExchangeResult(res, result);
  } catch (error: any) {
    console.error("Error offering streak assist:", error.message);
    res.status(500).json({ error: "Error offering streak assist" });
  }
}

/**
 * POST /users/streak-features/assist-request/:friendId — ask a friend to run
 * you a mile. Costs them nothing until they accept.
 */
export async function requestStreakAssistController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!streakFeaturesGloballyEnabled()) {
      return res.status(403).json({ error: "not_available" });
    }
    const result = await requestStreakAssist(req.userId!, req.params.friendId);
    return sendExchangeResult(res, result);
  } catch (error: any) {
    console.error("Error requesting streak assist:", error.message);
    res.status(500).json({ error: "Error requesting streak assist" });
  }
}

/**
 * POST /users/streak-features/assist-offers/:offerId — answer the half of an
 * exchange that's waiting on you. `{ "accept": true }` writes the coverage.
 */
export async function respondToAssistOfferController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!streakFeaturesGloballyEnabled()) {
      return res.status(403).json({ error: "not_available" });
    }
    const accept = req.body?.accept === true;
    const result = await respondToAssistOffer(
      req.userId!,
      req.params.offerId,
      accept,
    );
    return sendExchangeResult(res, result);
  } catch (error: any) {
    console.error("Error responding to streak assist offer:", error.message);
    res.status(500).json({ error: "Error responding to offer" });
  }
}
