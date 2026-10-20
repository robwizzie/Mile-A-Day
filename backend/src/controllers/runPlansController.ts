import { NextFunction, Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { isPlusActive } from "../services/plusService.js";
import {
  ADJUST_ACTIONS,
  ACTIONS,
  Action,
  Effort,
  FEELINGS,
  Feeling,
  addDays,
  isIsoDate,
  validateGoals,
} from "../services/runPlans/engine.js";
import {
  RunPlanError,
  adjustDay,
  applyProposal,
  archivePlan,
  createPlan,
  createProposal,
  declineProposal,
  getCurrentPlan,
  getFitness,
  recordCheckin,
  updatePlan,
  UpdatePlanInput,
} from "../services/runPlans/runPlanService.js";
import { revokeCoachTokens } from "../services/runPlans/coachConnection.js";

/**
 * Run Plans (Mile A Day+). Every route is self-scoped on the token; every
 * date is the client's LOCAL date. Reads send `?today=`, writes `today` in
 * the body. Validation answers 400 `{ error }`; engine refusals 422
 * `{ error: 'action_not_possible', cap_note }`.
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Plus gate: 403 `{ error: 'plus_required' }` for everyone else. */
export async function requirePlus(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  try {
    if (!(await isPlusActive(req.userId!))) return res.status(403).json({ error: "plus_required" });
    next();
  } catch (error) {
    console.error("[runPlans] plus check failed:", error);
    res.status(500).json({ error: "Error checking Mile A Day+" });
  }
}

class BadRequest extends Error {}

/**
 * The client's local today. Any real local date is within a day of UTC's;
 * two days of slack, anything further is a bad clock or a crafted request.
 */
function parseToday(raw: unknown, required = true): string {
  const utc = new Date().toISOString().slice(0, 10);
  if (raw == null || raw === "") {
    if (required) throw new BadRequest("invalid_today");
    return utc;
  }
  if (!isIsoDate(raw) || raw < addDays(utc, -2) || raw > addDays(utc, 2)) throw new BadRequest("invalid_today");
  return raw;
}

function parseEffort(raw: unknown): Effort {
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1 || n > 4) throw new BadRequest("invalid_effort");
  return n as Effort;
}

function parseHardDays(raw: unknown): number | null {
  if (raw === null) return null;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1 || n > 7) throw new BadRequest("invalid_hard_days");
  return n;
}

function parseFinishBy(raw: unknown, today: string): string | null {
  if (raw === null) return null;
  if (!isIsoDate(raw) || raw <= today || raw > addDays(today, 730)) throw new BadRequest("invalid_finish_by");
  return raw;
}

function parseGoals(raw: unknown) {
  const g = validateGoals(raw);
  if (typeof g === "string") throw new BadRequest("invalid_goals");
  return g;
}

function parseBool(raw: unknown, code: string): boolean {
  if (typeof raw !== "boolean") throw new BadRequest(code);
  return raw;
}

function optString(raw: unknown, max: number, code: string): string | null {
  if (raw == null) return null;
  if (typeof raw !== "string" || raw.length > max) throw new BadRequest(code);
  const t = raw.trim();
  return t.length ? t : null;
}

function handle(fn: (req: AuthenticatedRequest, res: Response) => Promise<unknown>) {
  return async (req: AuthenticatedRequest, res: Response) => {
    try {
      const out = await fn(req, res);
      if (!res.headersSent) res.json(out);
    } catch (e) {
      if (e instanceof BadRequest) return res.status(400).json({ error: e.message });
      if (e instanceof RunPlanError) return res.status(e.status).json({ error: e.code, ...e.extra });
      console.error("[runPlans] failed:", e);
      res.status(500).json({ error: "Error handling run plan" });
    }
  };
}

/** GET /run-plans/fitness?today= */
export const fitnessController = handle(async (req) => {
  const today = parseToday(req.query.today, false);
  return getFitness(req.userId!, today);
});

/** GET /run-plans/current?today= */
export const currentController = handle(async (req) => getCurrentPlan(req.userId!, parseToday(req.query.today)));

/** POST /run-plans { goals, effort, hard_days?, finish_by?, run_daily_mile, today } */
export const createController = handle(async (req) => {
  const b = req.body ?? {};
  const today = parseToday(b.today);
  return createPlan(
    req.userId!,
    {
      goals: parseGoals(b.goals),
      effort: parseEffort(b.effort),
      hard_days: b.hard_days === undefined ? null : parseHardDays(b.hard_days),
      finish_by: b.finish_by === undefined ? null : parseFinishBy(b.finish_by, today),
      run_daily_mile: b.run_daily_mile === undefined ? true : parseBool(b.run_daily_mile, "invalid_run_daily_mile"),
    },
    today,
  );
});

/** PATCH /run-plans/current { effort?, hard_days?, run_daily_mile?, claude_auto_apply?, goals?, finish_by?, today } */
export const updateController = handle(async (req) => {
  const b = req.body ?? {};
  const today = parseToday(b.today);
  const patch: UpdatePlanInput = {};
  if (b.effort !== undefined) patch.effort = parseEffort(b.effort);
  if (b.hard_days !== undefined) patch.hard_days = parseHardDays(b.hard_days);
  if (b.run_daily_mile !== undefined) patch.run_daily_mile = parseBool(b.run_daily_mile, "invalid_run_daily_mile");
  if (b.claude_auto_apply !== undefined) patch.claude_auto_apply = parseBool(b.claude_auto_apply, "invalid_claude_auto_apply");
  if (b.goals !== undefined) patch.goals = parseGoals(b.goals);
  if (b.finish_by !== undefined) patch.finish_by = parseFinishBy(b.finish_by, today);
  return updatePlan(req.userId!, patch, today);
});

/** DELETE /run-plans/current */
export const archiveController = handle(async (req) => archivePlan(req.userId!));

/** POST /run-plans/checkins { today, feeling?, message?, pain_flag? } */
export const checkinController = handle(async (req) => {
  const b = req.body ?? {};
  const today = parseToday(b.today);
  if (b.feeling != null && !FEELINGS.includes(b.feeling)) throw new BadRequest("invalid_feeling");
  const message = optString(b.message, 2000, "invalid_message");
  const pain = b.pain_flag === undefined ? false : parseBool(b.pain_flag, "invalid_pain_flag");
  if (b.feeling == null && !message && !pain) throw new BadRequest("empty_checkin");
  return recordCheckin(req.userId!, today, { feeling: (b.feeling ?? null) as Feeling | null, message, pain_flag: pain });
});

/** POST /run-plans/proposals { today, action, params?, summary?, rationale? } (source flamey) */
export const proposalController = handle(async (req) => {
  const b = req.body ?? {};
  const today = parseToday(b.today);
  if (!ACTIONS.includes(b.action)) throw new BadRequest("invalid_action");
  if (b.params != null && (typeof b.params !== "object" || Array.isArray(b.params))) throw new BadRequest("invalid_params");
  const params = (b.params ?? {}) as Record<string, unknown>;
  if (params.local_date !== undefined && !isIsoDate(params.local_date)) throw new BadRequest("invalid_params");
  return {
    proposal: await createProposal(
      req.userId!,
      today,
      {
        action: b.action as Action,
        params,
        summary: optString(b.summary, 500, "invalid_summary"),
        rationale: optString(b.rationale, 2000, "invalid_rationale"),
      },
      "flamey",
    ),
  };
});

function proposalId(req: AuthenticatedRequest): string {
  const id = String(req.params.id ?? "");
  if (!UUID.test(id)) throw new RunPlanError("proposal_not_found", 404);
  return id;
}

/** POST /run-plans/proposals/:id/apply { today } → current */
export const applyController = handle(async (req) => {
  const today = parseToday(req.body?.today ?? req.query.today);
  return applyProposal(req.userId!, proposalId(req), today);
});

/** POST /run-plans/proposals/:id/decline → { ok } */
export const declineController = handle(async (req) => declineProposal(req.userId!, proposalId(req)));

/** POST /run-plans/days/:date/adjust { action: easier|shorter|just_mile, today } → current */
export const adjustController = handle(async (req) => {
  const b = req.body ?? {};
  const today = parseToday(b.today);
  const date = req.params.date;
  if (!isIsoDate(date)) throw new BadRequest("invalid_date");
  if (!ADJUST_ACTIONS.has(b.action)) throw new BadRequest("invalid_action");
  return adjustDay(req.userId!, date, b.action, today);
});

/** DELETE /run-plans/claude — revoke every coach MCP token for the user. */
export const revokeClaudeController = handle(async (req) => {
  const revoked = await revokeCoachTokens(req.userId!);
  return { ok: true, revoked };
});
