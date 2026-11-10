import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import hasRequiredKeys from "../utils/hasRequiredKeys.js";
import { getSpecialEventsForUser } from "../services/specialEventService.js";

/** Special events showing now (Champ 5K Day), with the caller's numbers. `events` is empty between events. */
export async function getSpecialEvents(req: AuthenticatedRequest, res: Response) {
  if (!hasRequiredKeys(["userId"], req, res)) return;

  try {
    return res.status(200).json(await getSpecialEventsForUser(req.params.userId));
  } catch (error: any) {
    console.error("Error getting special events:", error.message);
    return res.status(500).json({ error: "Failed to load events" });
  }
}
