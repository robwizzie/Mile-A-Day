import { Request, Response } from "express";
import { getPublicStats } from "../services/publicStatsService.js";
import {
  addToAndroidWaitlist,
  normalizeWaitlistEmail,
} from "../services/waitlistService.js";

/** Global community counters for the marketing site. Aggregates only — the
 *  service layer is the gate for what may ever appear in this payload. */
export async function getPublicStatsController(_req: Request, res: Response) {
  try {
    const stats = await getPublicStats();
    res.json(stats);
  } catch (error) {
    console.error("Failed to fetch public stats:", error);
    res.status(500).json({ error: "Failed to fetch stats" });
  }
}

/** Android-launch waitlist signup from the marketing site. Responds the same
 *  for new and already-subscribed emails so addresses can't be enumerated. */
export async function joinAndroidWaitlistController(
  req: Request,
  res: Response,
) {
  const email = normalizeWaitlistEmail(req.body?.email);
  if (!email) {
    return res.status(400).json({ error: "A valid email is required" });
  }

  try {
    await addToAndroidWaitlist(email, "website");
    res.json({ ok: true });
  } catch (error) {
    console.error("Failed to save waitlist signup:", error);
    res.status(500).json({ error: "Failed to save signup" });
  }
}
