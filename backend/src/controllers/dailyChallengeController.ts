import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  getTodaysChallenge,
  getCompletions,
  getTodaysCompletion,
} from "../services/dailyChallengeService.js";
import { getCompletionDetail } from "../services/challengeCompletionDetailService.js";
import { signMediaUrlsDeep } from "../services/mediaSigningService.js";
import { areFriends } from "../services/friendshipService.js";
import { getMatchupHistory } from "../services/h2hMatchupService.js";
import { PostgresService } from "../services/DbService.js";
import hasRequiredKeys from "../utils/hasRequiredKeys.js";

const db = PostgresService.getInstance();

export async function getTodayForUser(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  try {
    const requesterId = req.userId;
    const targetUserId = req.params.userId;

    if (!requesterId)
      return res.status(401).json({ error: "Authentication required" });

    if (requesterId !== targetUserId) {
      const allowed = await areFriends(requesterId, targetUserId);
      if (!allowed)
        return res
          .status(403)
          .json({ error: "Access denied — not friends with this user" });
    }

    const localDate = await resolveUserLocalDate(targetUserId);

    if (requesterId === targetUserId) {
      // Full detail including progress, challenge payload, completion timestamp.
      const response = await getTodaysChallenge(targetUserId, localDate);
      return res.status(200).json(response);
    }

    // Friend view: lightweight completion status only.
    const completion = await getTodaysCompletion(targetUserId, localDate);
    return res.status(200).json(completion);
  } catch (err: any) {
    console.error("Error getting today's challenge:", err.message);
    return res
      .status(500)
      .json({ error: "Error getting today's challenge: " + err.message });
  }
}

export async function getCompletionsForUser(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  try {
    const completions = await getCompletions(req.params.userId);
    return res.status(200).json(completions);
  } catch (err: any) {
    console.error("Error getting challenge completions:", err.message);
    return res
      .status(500)
      .json({ error: "Error getting challenge completions: " + err.message });
  }
}

/**
 * How a past completion was earned — duel scores, the shared photo, who was
 * hyped/nudged, pace/distance/steps numbers. Fetched lazily when a completion
 * sheet opens. 404 when the date has no completion. The post section carries
 * a media url, so the payload is signed on the way out.
 */
export async function getCompletionDetailForUser(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!hasRequiredKeys(["userId", "localDate"], req, res)) return;

  const localDate = req.params.localDate;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(localDate)) {
    return res.status(400).json({ error: "localDate must be YYYY-MM-DD" });
  }

  try {
    const detail = await getCompletionDetail(req.params.userId, localDate);
    if (!detail) {
      return res
        .status(404)
        .json({ error: "No challenge completion for this date" });
    }
    return res.status(200).json(signMediaUrlsDeep(detail));
  } catch (err: any) {
    console.error("Error getting challenge completion detail:", err.message);
    return res.status(500).json({
      error: "Error getting challenge completion detail: " + err.message,
    });
  }
}

export async function getMatchupHistoryForUser(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  try {
    const history = await getMatchupHistory(req.params.userId);
    return res.status(200).json(history);
  } catch (err: any) {
    console.error("Error getting matchup history:", err.message);
    return res
      .status(500)
      .json({ error: "Error getting matchup history: " + err.message });
  }
}

async function resolveUserLocalDate(userId: string): Promise<string> {
  // Match existing pattern in workoutService.getTodayMiles: today in user's last-known timezone.
  const rows = await db.query<{ local_date: string }>(
    `SELECT (NOW() + (
			COALESCE(
				(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
				0
			) || ' minutes'
		)::interval)::date::text AS local_date`,
    [userId],
  );
  return rows[0]?.local_date ?? new Date().toISOString().slice(0, 10);
}
