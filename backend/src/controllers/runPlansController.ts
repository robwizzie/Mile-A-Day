import { NextFunction, Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import { isPlusActive } from "../services/plusService.js";
import { addDays, isIsoDate, OptionIntent, PROPOSAL_KINDS, ProposalKind } from "../services/runPlans/engine.js";
import * as svc from "../services/runPlans/runPlanService.js";
import { RunPlanError } from "../services/runPlans/runPlanService.js";
import {
  CallLogError,
  getAiStatus,
  setAnthropicConsent,
  setUserOptOut,
  uploadAiCalls,
} from "../services/runPlans/coachSettings.js";
import { ANTHROPIC_KINDS, AnthropicKind, runAnthropicCoach } from "../services/runPlans/anthropicCoach.js";
import { coachConnectionStatus, revokeCoachTokens } from "../services/runPlans/coachConnection.js";

/**
 * Run Plans v2 (Mile A Day+). Contract: /p/mad-run-plans-api. Self-scoped on
 * the token; dates are the phone's LOCAL dates (reads `?today=`, writes
 * `today` in the body). Errors are `{ error, ...extra }`.
 */

class BadRequest extends Error {}

function parseToday(raw: unknown): string {
  const utc = new Date().toISOString().slice(0, 10);
  if (raw == null || raw === "") return utc;
  if (!isIsoDate(raw) || raw < addDays(utc, -2) || raw > addDays(utc, 2)) throw new BadRequest("invalid_today");
  return raw;
}
const todayOf = (req: AuthenticatedRequest) => parseToday(req.method === "GET" || req.method === "DELETE" ? req.query.today : req.body?.today ?? req.query.today);

type Handler = (req: AuthenticatedRequest, res: Response) => Promise<unknown>;
const wrap = (fn: Handler, status = 200) => async (req: AuthenticatedRequest, res: Response) => {
  try {
    const out = await fn(req, res);
    if (!res.headersSent) res.status(status).json(out);
  } catch (e: any) {
    if (e instanceof BadRequest || e instanceof CallLogError) return res.status(e.message === "call_log_too_large" ? 413 : 400).json({ error: e.message });
    if (e instanceof RunPlanError) return res.status(e.status).json({ error: e.code, ...e.extra });
    console.error("[runPlans] request failed:", e);
    res.status(500).json({ error: "run_plans_error" });
  }
};

/** Plus gate: 403 `{ error: 'plus_required' }` for everyone else. */
export async function requirePlus(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  try {
    if (!(await isPlusActive(req.userId!))) return res.status(403).json({ error: "plus_required" });
    next();
  } catch (error) {
    console.error("[runPlans] plus check failed:", error);
    res.status(500).json({ error: "run_plans_error" });
  }
}

/** /coach/* tools need the AI Coach on for this user (any provider). */
async function requireAi(userId: string) {
  const ai = await getAiStatus(userId, true);
  if (ai.effective === "formula") throw new RunPlanError("ai_off", 403, { reason: ai.reason });
  return ai;
}

export const status = wrap(async (req) => svc.getStatus(req.userId!, await isPlusActive(req.userId!)));

export const getProfile = wrap(async (req) => {
  const p = await svc.getProfile(req.userId!);
  return { profile: p.profile, updated_at: p.updated_at };
});
export const putProfile = wrap(async (req) => svc.putProfile(req.userId!, req.body, todayOf(req)));

export const preview = wrap(async (req) => svc.previewPlan(req.userId!, req.body ?? {}, todayOf(req)));
export const create = wrap(async (req) => svc.createPlan(req.userId!, req.body ?? {}, todayOf(req)), 201);
export const current = wrap(async (req) => svc.getCurrent(req.userId!, todayOf(req)));
export const days = wrap(async (req) => {
  const today = todayOf(req);
  const from = req.query.from ?? today;
  const to = req.query.to ?? addDays(today, 13);
  if (!isIsoDate(from) || !isIsoDate(to)) throw new BadRequest("invalid_today");
  return { days: await svc.getDays(req.userId!, from, to, today) };
});
export const update = wrap(async (req) => {
  const { today: _t, ...patch } = req.body ?? {};
  return svc.updatePlan(req.userId!, patch, todayOf(req));
});
export const archive = wrap(async (req) => svc.archivePlan(req.userId!));
export const historyList = wrap(async (req) => svc.getHistory(req.userId!, Number(req.query.limit ?? 50) || 50, typeof req.query.before === "string" ? req.query.before : null));

export const listProposals = wrap(async (req) => ({
  proposals: await svc.listProposals(req.userId!, String(req.query.status ?? "pending"), Number(req.query.limit ?? 50) || 50, todayOf(req)),
}));
export const getProposal = wrap(async (req) => ({ proposal: await svc.getProposal(req.userId!, String(req.params.id), todayOf(req)) }));

/** Phone model (`apple`) or the user's own edit (`user`). Other sources are server-side only. */
export const submitProposal = wrap(async (req) => {
  const b = req.body ?? {};
  const source = b.source;
  if (source !== "apple" && source !== "user") throw new RunPlanError("invalid_source", 400);
  if (source === "apple") {
    const ai = await getAiStatus(req.userId!, true);
    if (ai.effective !== "apple") throw new RunPlanError("ai_mode_mismatch", 403, { effective: ai.effective });
  }
  const kind: ProposalKind = PROPOSAL_KINDS.includes(b.kind) ? b.kind : "adjust";
  if (!Array.isArray(b.changes)) throw new RunPlanError("invalid_day_spec", 400);
  const p = await svc.createProposal(
    req.userId!,
    {
      source,
      kind,
      title: String(b.title ?? ""),
      reason: String(b.reason ?? ""),
      goal_impact: b.goal_impact ?? null,
      changes: b.changes.map((c: any) => ({ local_date: c?.local_date, spec: c?.after })),
      deviation_reason: b.deviation_reason ?? null,
      ai_call_id: typeof b.ai_call_id === "string" && /^[0-9a-f-]{36}$/i.test(b.ai_call_id) ? b.ai_call_id : null,
    },
    todayOf(req),
  );
  return { proposal: p };
}, 201);

export const apply = wrap(async (req) => svc.applyProposal(req.userId!, String(req.params.id), todayOf(req)));
export const applyAfterRun = wrap(async (req) => svc.applyAfterRun(req.userId!, String(req.params.id), todayOf(req)));
export const decline = wrap(async (req) => svc.declineProposal(req.userId!, String(req.params.id), todayOf(req)));
export const undo = wrap(async (req) => svc.undoProposal(req.userId!, String(req.params.id), todayOf(req)));

export const open = wrap(async (req) => svc.openPlan(req.userId!, todayOf(req)));

export const checkin = wrap(async (req) => svc.recordCheckin(req.userId!, req.body ?? {}, todayOf(req)), 201);
export const listCheckins = wrap(async (req) => {
  const today = todayOf(req);
  const from = isIsoDate(req.query.from) ? req.query.from : addDays(today, -14);
  const to = isIsoDate(req.query.to) ? req.query.to : today;
  return { checkins: await svc.listCheckins(req.userId!, from, to) };
});
export const grade = wrap(async (req) => svc.submitGrade(req.userId!, req.body ?? {}, todayOf(req)));

// ─── Effort guess (RPE) ──────────────────────────────────────────────────
export const submitEffort = wrap(async (req) => svc.submitEffort(req.userId!, req.body ?? {}, todayOf(req)), 201);
export const listEfforts = wrap(async (req) => {
  const today = todayOf(req);
  const from = isIsoDate(req.query.from) ? req.query.from : addDays(today, -30);
  const to = isIsoDate(req.query.to) ? req.query.to : today;
  return svc.listEfforts(req.userId!, from, to);
});
export const getEffort = wrap(async (req) => svc.getEffort(req.userId!, String(req.params.workoutId)));
export const rateEffort = wrap(async (req) => svc.rateEffort(req.userId!, String(req.params.workoutId), req.body ?? {}, todayOf(req)));

// ─── Coach settings ──────────────────────────────────────────────────────
export const patchCoachSettings = wrap(async (req) => {
  if (typeof req.body?.user_opt_out !== "boolean") throw new BadRequest("invalid_source");
  await setUserOptOut(req.userId!, req.body.user_opt_out);
  return getAiStatus(req.userId!, true);
});
export const anthropicConsent = wrap(async (req) => {
  if (typeof req.body?.accepted !== "boolean") throw new BadRequest("invalid_source");
  await setAnthropicConsent(req.userId!, req.body.accepted);
  return getAiStatus(req.userId!, true);
});

// ─── Coach tools ─────────────────────────────────────────────────────────
export const coachContext = wrap(async (req) => {
  await requireAi(req.userId!);
  return svc.getCoachContext(req.userId!, todayOf(req), Number(req.query.days_back ?? 14) || 14, Number(req.query.days_ahead ?? 14) || 14);
});
export const coachOptions = wrap(async (req) => {
  await requireAi(req.userId!);
  const b = req.body ?? {};
  const intents: OptionIntent[] = ["easier", "shorter", "longer", "harder", "swap_walk", "move_key", "fit_time"];
  if (!isIsoDate(b.local_date) || !intents.includes(b.intent)) throw new BadRequest("invalid_day_spec");
  return svc.coachOptions(req.userId!, todayOf(req), b.local_date, b.intent, { minutes: b.minutes != null ? Number(b.minutes) : undefined, to_date: isIsoDate(b.to_date) ? b.to_date : undefined });
});
export const coachBuildDay = wrap(async (req) => {
  await requireAi(req.userId!);
  const b = req.body ?? {};
  if (!isIsoDate(b.local_date) || !b.day) throw new BadRequest("invalid_day_spec");
  return svc.coachBuildDay(req.userId!, todayOf(req), b.local_date, b.day);
});
export const coachValidate = wrap(async (req) => {
  await requireAi(req.userId!);
  return svc.coachValidate(req.userId!, todayOf(req), req.body?.changes);
});
export const coachEstimate = wrap(async (req) => {
  await requireAi(req.userId!);
  return svc.coachEstimate(req.userId!, String(req.query.distance ?? "5k"), req.query.distance_mi != null ? Number(req.query.distance_mi) : null);
});
export const coachNotes = wrap(async (req) => {
  const ai = await requireAi(req.userId!);
  const source = req.body?.source ?? ai.effective;
  if (source !== ai.effective) throw new RunPlanError("ai_mode_mismatch", 403, { effective: ai.effective });
  return svc.putCoachNotes(req.userId!, todayOf(req), source, req.body?.notes, req.body?.grade_summaries);
});
export const coachCalls = wrap(async (req) => {
  await requireAi(req.userId!);
  return uploadAiCalls(req.userId!, req.body?.calls);
});
export const coachAnthropic = wrap(async (req) => {
  const b = req.body ?? {};
  if (!ANTHROPIC_KINDS.includes(b.kind)) throw new BadRequest("invalid_source");
  if (b.message != null && (typeof b.message !== "string" || b.message.length > 2000)) throw new BadRequest("invalid_checkin");
  return runAnthropicCoach(req.userId!, { today: todayOf(req), kind: b.kind as AnthropicKind, message: b.message ?? null, checkin_id: typeof b.checkin_id === "string" && /^[0-9a-f-]{36}$/i.test(b.checkin_id) ? b.checkin_id : null });
});

/** GET /run-plans/claude — is the runner's own Claude (coach MCP) connected? No Plus gate: it's their sign-in. */
export const claudeConnection = wrap(async (req) => coachConnectionStatus(req.userId!));
/** DELETE /run-plans/claude — revoke every coach MCP sign-in for the user (works after Plus lapses too). */
export const revokeClaude = wrap(async (req) => ({ ok: true, revoked: await revokeCoachTokens(req.userId!) }));
