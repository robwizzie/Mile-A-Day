/**
 * Overseer tools on the admin database connector (spec §11): the admin's
 * Claude audits the AI Coach and can run the admin's OWN plan.
 *
 * Same door as `query`/`execute`: `isUserAllowed` (MCP_ALLOWED_USERS +
 * role = 'admin') already ran on this request. Each tool checks role = admin
 * again itself (a role demoted mid-request, or a future second mount, must
 * not reach these), and every call is audited BEFORE it runs (`audited`).
 *
 * These go through the app's services on the app's pool — never SQL — so the
 * engine computes every number and `validateChanges` checks every change:
 *   - `propose_plan_change`: a PENDING proposal (source 'overseer') on any
 *     user's plan; the user decides in the app.
 *   - `set_plan`: applies directly, admin's own plan only, and only with
 *     `confirmed_in_chat: true` + the `summary` that was shown
 *     (`applyOverseerChange` enforces all three).
 */
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { PostgresService } from "../services/DbService.js";
import { addDays, isIsoDate } from "../services/runPlans/engine.js";
import {
  RunPlanError,
  applyOverseerChange,
  getPlanDetailForAdmin,
  proposeOverseerChange,
  type OverseerChange,
} from "../services/runPlans/runPlanService.js";
import { coachCallDetail, createReviewNote, listCoachCallsFull, listRunPlansForAdmin } from "../services/runPlans/adminCoachService.js";
import { changesSchema, cleanDaySpec } from "../services/runPlans/mcpSchemas.js";
import { SCOPE_READ, SCOPE_WRITE } from "./config.js";
import { audited, errorText, type Caller } from "./dbTools.js";

const db = PostgresService.getInstance();

type Reply = { content: { type: "text"; text: string }[]; isError?: boolean };
const reply = (value: unknown): Reply => ({ content: [{ type: "text", text: typeof value === "string" ? value : JSON.stringify(value, null, 1) }] });
const refuse = (t: string): Reply => ({ content: [{ type: "text", text: t }], isError: true });

/** Thrown before the service runs; rendered as an isError reply. */
class ToolRefusal extends Error {}

async function requireAdmin(userId: string): Promise<void> {
  const r = await db.query<{ role: string | null }>(`SELECT role FROM users WHERE user_id = $1`, [userId]);
  if (r[0]?.role !== "admin") throw new ToolRefusal("admin_required: these tools are for admins only.");
}

/** `@dave`, `dave` or a user_id → { user_id, username }. */
async function resolveUser(ref: string): Promise<{ user_id: string; username: string | null }> {
  const s = ref.trim().replace(/^@/, "");
  const r = await db.query<{ user_id: string; username: string | null }>(
    `SELECT user_id, username FROM users WHERE user_id = $1 OR lower(username) = lower($1) ORDER BY (user_id = $1) DESC LIMIT 1`,
    [s],
  );
  if (!r[0]) throw new ToolRefusal(`user_not_found: no user "${ref}".`);
  return r[0];
}

/** The phone's local date rule (±2 days of UTC), defaulting to UTC's date. */
function todayFrom(raw: string | undefined): string {
  const utc = new Date().toISOString().slice(0, 10);
  if (raw === undefined) return utc;
  if (!isIsoDate(raw) || raw < addDays(utc, -2) || raw > addDays(utc, 2)) throw new ToolRefusal("invalid_today: today must be YYYY-MM-DD within 2 days of UTC's date.");
  return raw;
}

const toChange = (a: { title?: string; reason?: string; changes: z.infer<typeof changesSchema>; deviation_reason?: string }): OverseerChange => ({
  title: a.title,
  reason: a.reason,
  deviation_reason: a.deviation_reason ?? null,
  changes: a.changes.map((c) => ({ local_date: c.local_date, day: cleanDaySpec(c.day) })),
});

/** Service errors keep their code and detail (violations, deviations) so Claude can fix and retry. */
function failure(err: unknown): Reply {
  if (err instanceof ToolRefusal) return refuse(err.message);
  if (err instanceof RunPlanError) return refuse(JSON.stringify({ error: err.code, ...err.extra }));
  return refuse(`Failed: ${errorText(err)}`);
}

export function registerRunPlanTools(server: McpServer, caller: Caller, can: (scope: string) => boolean): void {
  const run = (tool: string, scope: string, args: unknown, fn: () => Promise<unknown>) => async (): Promise<Reply> => {
    if (!can(scope)) return refuse(`This sign-in lacks the ${scope} scope.`);
    try {
      await requireAdmin(caller.userId);
      return reply(await audited(caller, tool, args, scope === SCOPE_WRITE, fn));
    } catch (err) {
      return failure(err);
    }
  };

  server.registerTool(
    "list_run_plans",
    {
      title: "Every user's run plan",
      description:
        "Every active Run Plan: user, goals, runs/week, difficulty, AI mode (off/apple/anthropic), grades in the last 28 days " +
        "(count, average 0–100), last change, pending proposals. Start here to pick a plan to audit.",
      inputSchema: { limit: z.number().int().min(1).max(1000).default(200) },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ limit }) => run("list_run_plans", SCOPE_READ, { limit }, async () => ({ plans: await listRunPlansForAdmin(limit ?? 200) }))(),
  );

  server.registerTool(
    "get_run_plan_detail",
    {
      title: "One plan's full history",
      description:
        "A user's active plan in full: the plan, fitness profile, days (6 weeks back, 4 ahead, with status and grades), " +
        "every proposal with its before/after days, checks and decision, check-ins, grades, post-run effort ratings " +
        "(guess vs the runner's RPE, `efforts`) with per-type calibration (`effort_calibration`), goal estimates and the plan history log. " +
        "Health-derived data: admins only, don't paste it anywhere else.",
      inputSchema: { user: z.string().min(1).max(80).describe("Username (with or without @) or user_id.") },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ user }) =>
      run("get_run_plan_detail", SCOPE_READ, { user }, async () => {
        const u = await resolveUser(user);
        return { user: u, ...(await getPlanDetailForAdmin(u.user_id)) };
      })(),
  );

  server.registerTool(
    "get_coach_calls",
    {
      title: "The AI Coach's exact inputs and outputs",
      description:
        "A user's AI Coach calls, newest first, with the FULL input and output of each, provider, model, tokens, cost (USD), " +
        "latency and errors. Pass call_id for one call. Page older calls with `before` (the created_at of the last one you got). " +
        "Kept 90 days. Health-derived: admins only.",
      inputSchema: {
        user: z.string().min(1).max(80).optional().describe("Username or user_id. Required unless call_id is given."),
        call_id: z.string().uuid().optional(),
        limit: z.number().int().min(1).max(25).default(10),
        before: z.string().max(40).optional().describe("ISO timestamp: only calls created before it."),
      },
      annotations: { readOnlyHint: true, openWorldHint: false },
    },
    async ({ user, call_id, limit, before }) =>
      run("get_coach_calls", SCOPE_READ, { user, call_id, limit, before }, async () => {
        if (call_id) return coachCallDetail(call_id);
        if (!user) throw new ToolRefusal("Pass user or call_id.");
        const u = await resolveUser(user);
        return { user: u, calls: await listCoachCallsFull(u.user_id, limit ?? 10, before ?? null) };
      })(),
  );

  server.registerTool(
    "review_note",
    {
      title: "Save a review finding",
      description:
        "Save a finding about the coach to the review log on the admin Coach tab (source 'overseer'), e.g. " +
        "\"adjustment on Nov 20 passed the spike rule by 0.1 mi; too thin after a missed week\". Be specific: date, rule, numbers. " +
        "Optionally tie it to a plan_id and proposal_id from get_run_plan_detail.",
      inputSchema: {
        user: z.string().min(1).max(80).describe("Whose plan the note is about (username or user_id)."),
        body: z.string().min(1).max(4000),
        plan_id: z.string().uuid().optional(),
        proposal_id: z.string().uuid().optional(),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async ({ user, body, plan_id, proposal_id }) =>
      run("review_note", SCOPE_WRITE, { user, body, plan_id, proposal_id }, async () => {
        const u = await resolveUser(user);
        return { note: await createReviewNote(caller.userId, { user_id: u.user_id, plan_id: plan_id ?? null, proposal_id: proposal_id ?? null, body }, "overseer") };
      })(),
  );

  const changeArgs = {
    title: z.string().min(1).max(200).describe("Short, shown to the user, e.g. \"Easier Thursday\"."),
    reason: z.string().min(1).max(600).describe("Why, in plain words, shown to the user."),
    changes: changesSchema.describe("The days to change: local_date (YYYY-MM-DD, today or later, inside the plan) and the new DaySpec."),
    deviation_reason: z
      .string()
      .max(600)
      .optional()
      .describe("Required when the change breaks a convention rule (ramp, cutback size); hard rules (spike guard, back-to-back hard days) can never be broken."),
    today: z.string().optional().describe("The user's local date, YYYY-MM-DD. Default: UTC's date."),
  };

  server.registerTool(
    "propose_plan_change",
    {
      title: "Suggest a change to someone's plan",
      description:
        "Create a PENDING proposal on any user's plan, source 'overseer'. Nothing changes until that user taps Apply in the app. " +
        "The server recomputes every number from the DaySpecs and validates the change; a hard-rule violation or a missing " +
        "deviation_reason comes back as an error with the details, so adjust and retry. A newer proposal on the same dates " +
        "replaces an unanswered older one.",
      inputSchema: { user: z.string().min(1).max(80).describe("Username or user_id."), ...changeArgs },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async (a) =>
      run("propose_plan_change", SCOPE_WRITE, a, async () => {
        const u = await resolveUser(a.user);
        const today = todayFrom(a.today);
        return { proposal: await proposeOverseerChange(caller.userId, u.user_id, toChange(a), today) };
      })(),
  );

  server.registerTool(
    "set_plan",
    {
      title: "Change YOUR OWN plan directly",
      description:
        "Apply a change to the signed-in admin's OWN plan immediately, with no in-app approval. Never another user's plan " +
        "(use propose_plan_change for those). BEFORE calling this you MUST show the admin, in the chat, the exact change " +
        "(every date, before → after, and the week's mileage) and get an explicit yes to that exact change in their reply. " +
        "Only then call it with confirmed_in_chat: true and `summary` set to the change exactly as you showed it. Without " +
        "that yes, don't call it; if anything about the change differs from what they approved, ask again. The change is " +
        "still validated (hard rules always apply) and can be undone in the app for 24 hours; the plan history records it " +
        "as 'overseer_set_plan' with your summary.",
      inputSchema: {
        ...changeArgs,
        confirmed_in_chat: z.boolean().describe("true ONLY if the admin said yes in this chat to exactly this change."),
        summary: z.string().max(2000).describe("The change exactly as you showed it to the admin."),
        user: z.string().max(80).optional().describe("Leave out. If given it must be the signed-in admin; anyone else is refused."),
      },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
    },
    async (a) =>
      run("set_plan", SCOPE_WRITE, a, async () => {
        const target = a.user ? (await resolveUser(a.user)).user_id : undefined;
        const today = todayFrom(a.today);
        return applyOverseerChange(caller.userId, toChange(a), {
          confirmed_in_chat: a.confirmed_in_chat,
          summary: a.summary,
          target_user_id: target,
          today,
        });
      })(),
  );
}

export const RUN_PLAN_TOOL_NAMES = ["get_coach_calls", "get_run_plan_detail", "list_run_plans", "propose_plan_change", "review_note", "set_plan"];
