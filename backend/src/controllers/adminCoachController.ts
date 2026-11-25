import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import * as svc from "../services/runPlans/adminCoachService.js";
import { RunPlanError } from "../services/runPlans/runPlanService.js";

/** Admin Coach tab (mounted under /admin, which is authenticateToken + requireAdmin). */
type Handler = (req: AuthenticatedRequest) => Promise<unknown>;
const wrap = (fn: Handler, status = 200) => async (req: AuthenticatedRequest, res: Response) => {
  try {
    res.status(status).json(await fn(req));
  } catch (e: any) {
    if (e instanceof RunPlanError) return res.status(e.status).json({ error: e.code, ...e.extra });
    console.error("[admin/coach] request failed:", e);
    res.status(500).json({ error: "admin_coach_error" });
  }
};

export const usage = wrap((req) => svc.coachUsage(Number(req.query.days ?? 30) || 30));
export const spend = wrap((req) => svc.coachSpend(typeof req.query.month === "string" ? req.query.month : undefined));
export const users = wrap((req) => svc.coachUsers(typeof req.query.q === "string" ? req.query.q.slice(0, 60) : null, Number(req.query.limit ?? 50) || 50, Number(req.query.offset ?? 0) || 0));
export const userDetail = wrap((req) => svc.coachUserDetail(String(req.params.userId)));
export const callDetail = wrap((req) => svc.coachCallDetail(String(req.params.id)));
export const setAiMode = wrap((req) => svc.adminSetAiMode(req.userId!, String(req.params.userId), req.body?.ai_mode));
export const getSettings = wrap(() => svc.adminGetCoachSettings());
export const putSettings = wrap((req) => svc.adminPutCoachSettings(req.userId!, req.body));
export const listNotes = wrap(async (req) => ({ notes: await svc.listReviewNotes(String(req.query.status ?? "open")) }));
export const createNote = wrap((req) => svc.createReviewNote(req.userId!, req.body ?? {}, "admin"), 201);
export const patchNote = wrap((req) => svc.setReviewNoteStatus(String(req.params.id), req.body?.status));
export const plans = wrap(async () => ({ plans: await svc.listRunPlansForAdmin() }));
