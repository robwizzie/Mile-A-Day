import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import hasRequiredKeys from "../utils/hasRequiredKeys.js";
import {
  getWeeklyRecap as buildWeeklyRecap,
  WeeklyRecapRequestError,
} from "../services/weeklyRecapService.js";
import { signMediaUrlsDeep } from "../services/mediaSigningService.js";

/**
 * The user's week in review. Self-only (`requireSelfAccess` on the route): it
 * carries the viewer's friend circle and their standings in it.
 *
 * `week_start` is optional; the response always says which week it chose.
 */
export async function getWeeklyRecap(
  req: AuthenticatedRequest,
  res: Response,
) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  const raw = req.query.week_start;
  if (raw !== undefined && typeof raw !== "string") {
    return res.status(400).json({
      error: "week_start must be a YYYY-MM-DD date",
      code: "invalid_week_start",
    });
  }

  try {
    const recap = await buildWeeklyRecap(req.params.userId, raw || undefined);
    return res.status(200).json(signMediaUrlsDeep(recap));
  } catch (error: any) {
    if (error instanceof WeeklyRecapRequestError) {
      return res.status(400).json({ error: error.message, code: error.code });
    }
    console.error("Error getting weekly recap:", error.message);
    return res.status(500).json({ error: "Error getting weekly recap" });
  }
}
