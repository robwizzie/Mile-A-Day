import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { recordDiagnostics } from "../services/diagnosticsService.js";

/**
 * POST /diagnostics/metrickit
 * { app_version, build, os_version, device_model,
 *   items: [{ id, kind, occurred_at, diagnostic }] }
 *
 * The client clears its retry queue on ANY 2xx, so a batch the server only
 * partly wanted (capped, duplicate, malformed items) is still a 200 with the
 * counts — retrying it would only be refused again. 400 is reserved for a
 * body with no `items` array at all.
 */
export async function recordMetricKitController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const body = req.body ?? {};
  if (!Array.isArray(body.items)) {
    return res.status(400).json({ error: "items array required" });
  }
  try {
    const result = await recordDiagnostics(req.userId!, body, body.items);
    res.status(200).json(result);
  } catch (error: any) {
    console.error("Error recording diagnostics:", error.message);
    res.status(500).json({ error: "Error recording diagnostics" });
  }
}
