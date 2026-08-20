import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { BadRequestError } from "../errors/Errors.js";
import {
  endInjuryPause,
  getInjuryPauseStatus,
  isValidIsoDate,
  startInjuryPause,
} from "../services/injuryPauseService.js";

/**
 * Injury pause ("Recovery Mode") controllers.
 *
 * Every handler is self-scoped on the token — there is no :userId path param,
 * so requireSelfAccess has nothing to check. Pausing your own streak is the
 * only thing these endpoints can do.
 */

/**
 * Map a service-level BadRequestError to a 400 carrying its code, and anything
 * else to a generic 500 — never leak raw error text (matches the global handler
 * in server.ts).
 */
function handleError(res: Response, error: unknown, logLabel: string): void {
  if (error instanceof BadRequestError) {
    res.status(400).json({ error: error.message });
    return;
  }
  console.error(`Error ${logLabel}:`, error);
  res.status(500).json({ error: `Error ${logLabel}` });
}

/** GET /streak/pause — status, limits, and why you can't pause if you can't. */
export async function injuryPauseStatusController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    res.json(await getInjuryPauseStatus(req.userId!));
  } catch (error) {
    handleError(res, error, "loading injury pause status");
  }
}

/**
 * POST /streak/pause — open a pause, optionally backdated.
 *
 * `started_on` is shape-checked HERE rather than trusted to the service: an
 * unvalidated body value reaches a `$2::date` cast and surfaces as a 500
 * instead of the 400 the client knows how to read. How far back it may be
 * dated is the service's rule (it needs the caller's local today), so this
 * only asserts the format.
 */
export async function startInjuryPauseController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const startedOn = req.body?.started_on;
    // isValidIsoDate round-trips through the calendar, so 2026-02-31 is
    // rejected here rather than silently rolling into March at the ::date cast.
    if (
      startedOn !== undefined &&
      startedOn !== null &&
      !isValidIsoDate(startedOn)
    ) {
      return res.status(400).json({ error: "invalid_started_on" });
    }
    // Absent stays absent: the service defaults it to the caller's local
    // today, which the server is the only side that can compute.
    res.json(
      await startInjuryPause(
        req.userId!,
        startedOn === null ? undefined : (startedOn as string | undefined),
      ),
    );
  } catch (error) {
    handleError(res, error, "starting injury pause");
  }
}

/** DELETE /streak/pause — resume, once the minimum has elapsed. */
export async function endInjuryPauseController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    res.json(await endInjuryPause(req.userId!));
  } catch (error) {
    handleError(res, error, "ending injury pause");
  }
}
