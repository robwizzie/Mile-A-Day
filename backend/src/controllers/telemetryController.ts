import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { recordFeatureEvent } from "../services/telemetryService.js";

/** POST /telemetry/feature { feature } — fire-and-forget usage ping. */
export async function recordFeatureEventController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const feature = typeof req.body?.feature === "string" ? req.body.feature : "";
    const recorded = await recordFeatureEvent(req.userId!, feature);
    // 200 either way: an unknown feature (older/newer client skew) is not the
    // client's problem, and nothing user-facing depends on this write.
    res.status(200).json({ recorded });
  } catch (error: any) {
    console.error("Error recording feature event:", error.message);
    res.status(500).json({ error: "Error recording event" });
  }
}
