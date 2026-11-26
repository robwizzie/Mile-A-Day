/**
 * Coach MCP tools (Run Plans v2): the runner's OWN Claude reads their plan,
 * runs and check-ins and PROPOSES changes. Every tool is scoped to the
 * signed-in user (the token's user id; no tool takes a user argument), checks
 * Mile A Day+ on every call, and goes through the Run Plans service, so the
 * engine computes every number and `validateChanges` checks every change.
 *
 * Proposal-only: `propose_change` creates a PENDING proposal with source
 * 'user_claude'; the runner applies or keeps it in the app. Nothing here
 * applies a change, takes SQL, or reads anyone else.
 */
import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { AuthInfo } from "@modelcontextprotocol/sdk/server/auth/types.js";
import { PostgresService } from "../services/DbService.js";
import { isPlusActive } from "../services/plusService.js";
import { userTodaySql } from "../services/streakFeatureCore.js";
import { addDays, isIsoDate } from "../services/runPlans/engine.js";
import {
  RunPlanError,
  createProposal,
  getCurrent,
  getDays,
  getProfile,
  getRuns,
  listEfforts,
  listCheckins,
  listProposals,
} from "../services/runPlans/runPlanService.js";
import { changesSchema, cleanDaySpec } from "../services/runPlans/mcpSchemas.js";
import { recordToolCall } from "./audit.js";

const db = PostgresService.getInstance();

type Reply = { content: { type: "text"; text: string }[]; isError?: boolean };
const json = (v: unknown): Reply => ({ content: [{ type: "text", text: JSON.stringify(v, null, 1) }] });
const fail = (t: string): Reply => ({ content: [{ type: "text", text: t }], isError: true });

class ToolInputError extends Error {}

const date = () => z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "YYYY-MM-DD");
const todayParam = date()
  .optional()
  .describe(
    "The runner's LOCAL date today, YYYY-MM-DD. Pass it when you know it; if omitted, the server derives it from the " +
      "timezone of their most recent workout (UTC if none).",
  );

/** The runner's local today: the given one (sanity-checked) or derived. */
async function resolveToday(userId: string, given: string | undefined): Promise<string> {
  const utc = new Date().toISOString().slice(0, 10);
  if (given !== undefined) {
    // Every timezone is within a day of UTC; the app allows the same ±2 window.
    if (!isIsoDate(given) || given < addDays(utc, -2) || given > addDays(utc, 2)) {
      throw new ToolInputError(`today must be the runner's local date (within 2 days of ${utc}); got ${given}`);
    }
    return given;
  }
  const rows = await db.query<{ today: string }>(`SELECT (${userTodaySql("u")})::text AS today FROM users u WHERE u.user_id = $1`, [userId]);
  return rows[0]?.today ?? utc;
}

function checkDate(name: string, v: string | undefined): void {
  if (v !== undefined && !isIsoDate(v)) throw new ToolInputError(`${name} must be a real date, YYYY-MM-DD`);
}

function errorReply(err: unknown): Reply {
  if (err instanceof ToolInputError) return fail(err.message);
  if (err instanceof RunPlanError) {
    if (err.code === "no_active_plan") {
      return fail("no_active_plan: this runner has no active run plan. They create one in the Mile A Day app (Run Plan).");
    }
    // Violations / deviations carry the details Claude needs to fix the proposal.
    return fail(JSON.stringify({ error: err.code, status: err.status, ...err.extra }));
  }
  console.error("[coach-mcp] tool failed", err);
  return fail("Something went wrong on the Mile A Day side. Try again in a moment.");
}

export const SERVER_INSTRUCTIONS =
  "You are coaching ONE Mile A Day runner: the person who signed in. You can read their run plan, runs and " +
  "check-ins, and PROPOSE changes to the plan. You cannot see or change anything else, or anyone else.\n" +
  "Rules of the plan:\n" +
  "- The plan engine computes every number (paces, segments, totals) from a DaySpec. You choose the kind and shape " +
  "of a day; you never type paces. Don't state a number the tools didn't give you.\n" +
  "- Every change is a PENDING proposal: the runner taps Apply, Apply after the run, or Keep in the app. Say so.\n" +
  "- Hard rules (single-run spike guard; no two hard days in a row) can never be broken. Convention rules (weekly " +
  "ramp, cutback size, taper) may be, with a deviation_reason.\n" +
  "- Dates are the runner's LOCAL YYYY-MM-DD. Pass `today` (their local date) when you know it.\n" +
  "- Units: miles; paces and durations in seconds (pace = seconds per mile).\n" +
  "- This is fitness coaching, not medical advice. No diet or calorie-deficit advice. If they report pain, injury " +
  "or illness, suggest an easier day or rest and seeing a doctor; never push through pain.\n" +
  "Start with get_profile and get_plan; look at get_runs, get_checkins and list_proposals before proposing anything.";

const PROPOSE_DESCRIPTION =
  "Propose a change to the runner's plan: one or more days (today or later, inside the plan), each with a new DaySpec. " +
  "The server fills in the day as it is now, computes every number of the new day, and validates the whole change " +
  "set. A hard-rule violation (spike_guard, no_back_to_back_hard) or a convention deviation without deviation_reason " +
  "comes back as an error listing what failed: adjust and retry, don't resend the same thing. A new proposal on a " +
  "date replaces an unanswered older one there. Returns {proposal}: status 'pending' until the runner decides in the " +
  "app; proposal.changes lists each day before/after and proposal.checks the weekly mileage and rules passed. Make " +
  "one well-explained proposal rather than many.";

export function buildCoachServer(auth: AuthInfo): McpServer {
  const userId = String(auth.extra?.userId);
  const grantId = String(auth.extra?.grantId);
  const server = new McpServer({ name: "mile-a-day-coach", version: "2.0.0" }, { instructions: SERVER_INSTRUCTIONS });

  /** Plus check, then the body; audit row + uniform error replies either way. */
  const run = async (tool: string, args: unknown, body: () => Promise<unknown>): Promise<Reply> => {
    const t0 = Date.now();
    let reply: Reply;
    let outcome: "ok" | "error" = "ok";
    try {
      if (!(await isPlusActive(userId))) throw new ToolInputError("plus_required: Run Plans are part of Mile A Day+. The runner's membership isn't active.");
      reply = json(await body());
    } catch (err) {
      reply = errorReply(err);
      outcome = "error";
    }
    await recordToolCall({ userId, grantId, tool, args, outcome, detail: outcome === "error" ? reply.content[0].text : null, durationMs: Date.now() - t0 });
    return reply;
  };

  const read = { readOnlyHint: true, openWorldHint: false } as const;

  server.registerTool(
    "get_profile",
    {
      title: "Runner profile",
      description:
        "The runner's plan settings (goals, target date, runs per week, difficulty 1 Easy does it · 2 Steady · 3 Push · " +
        "4 All in, walk mode, coach notes) and the fitness profile the phone computed from their runs (weekly miles, " +
        "longest recent run, heart-rate zones, VDOT, race estimates, experience). plan is null without an active plan.",
      inputSchema: { today: todayParam },
      annotations: read,
    },
    async (args) =>
      run("get_profile", args, async () => {
        const today = await resolveToday(userId, args.today);
        const { profile, updated_at } = await getProfile(userId);
        let plan: unknown = null;
        try {
          plan = (await getCurrent(userId, today)).plan;
        } catch (e) {
          if (!(e instanceof RunPlanError && e.code === "no_active_plan")) throw e;
        }
        return { today, plan, fitness_profile: profile, fitness_profile_at: updated_at };
      }),
  );

  server.registerTool(
    "get_plan",
    {
      title: "Plan days",
      description:
        "Plan days: kind, title, distance_mi, segments (paces, HR, durations), note, status (planned | today | done | " +
        "partial | missed | walk_done), the run that completed it, and its spec (the DaySpec it was built from). " +
        "Without from/to: this Monday–Sunday week, today, the next run and pending proposals. With from/to (≤ 120 days): " +
        "just those days.",
      inputSchema: {
        today: todayParam,
        from: date().optional().describe("First day, YYYY-MM-DD (with `to`)."),
        to: date().optional().describe("Last day, YYYY-MM-DD (with `from`)."),
      },
      annotations: read,
    },
    async (args) =>
      run("get_plan", args, async () => {
        checkDate("from", args.from);
        checkDate("to", args.to);
        const today = await resolveToday(userId, args.today);
        if (args.from || args.to) {
          const from = args.from ?? args.to!;
          const to = args.to ?? args.from!;
          return { today, from, to, days: await getDays(userId, from, to, today) };
        }
        const cur = await getCurrent(userId, today);
        return { today, plan: cur.plan, today_day: cur.today, week: cur.week, next_run: cur.next_run, pending_proposals: cur.pending_proposals, suggestions: cur.suggestions };
      }),
  );

  server.registerTool(
    "get_runs",
    {
      title: "Runs",
      description:
        "The runner's counted runs in [from, to] (≤ 120 days; default the last 28 days): local date, distance, " +
        "duration, moving time and per-mile splits. include_walks adds walks and hikes. `efforts` = post-run effort " +
        "guesses (RPE 1–10) and the runner's own rating per workout; `effort_calibration` = how far their ratings sit from the guesses per run type.",
      inputSchema: { today: todayParam, from: date().optional(), to: date().optional(), include_walks: z.boolean().optional() },
      annotations: read,
    },
    async (args) =>
      run("get_runs", args, async () => {
        checkDate("from", args.from);
        checkDate("to", args.to);
        const today = await resolveToday(userId, args.today);
        const to = args.to ?? today;
        const from = args.from ?? addDays(to, -27);
        const [runs, eff] = await Promise.all([getRuns(userId, from, to, args.include_walks === true), listEfforts(userId, from, to)]);
        return { from, to, runs, efforts: eff.efforts, effort_calibration: eff.calibration };
      }),
  );

  server.registerTool(
    "get_checkins",
    {
      title: "Check-ins",
      description:
        "Pre-run check-ins, newest first: time available (min), energy and soreness (0–10), how much further they " +
        "wanted to go, their free text. Default range: the last 30 days (≤ 366).",
      inputSchema: { today: todayParam, from: date().optional(), to: date().optional() },
      annotations: read,
    },
    async (args) =>
      run("get_checkins", args, async () => {
        checkDate("from", args.from);
        checkDate("to", args.to);
        const today = await resolveToday(userId, args.today);
        const to = args.to ?? today;
        let from = args.from ?? addDays(to, -29);
        if (from < addDays(to, -366)) from = addDays(to, -366);
        return { from, to, checkins: await listCheckins(userId, from, to) };
      }),
  );

  server.registerTool(
    "list_proposals",
    {
      title: "Proposals",
      description:
        "Change proposals on the active plan, newest first, from every coach (formula = the plan's rules, apple / " +
        "anthropic = the in-app AI Coach, overseer = the Mile A Day team, user_claude = you, user = the runner): status, " +
        "each day's before/after, checks, and when it was decided. Check this before proposing so you don't repeat one " +
        "the runner already declined.",
      inputSchema: {
        today: todayParam,
        status: z.enum(["pending", "scheduled", "all"]).optional().describe("Default pending."),
        limit: z.number().int().min(1).max(100).optional(),
      },
      annotations: read,
    },
    async (args) =>
      run("list_proposals", args, async () => {
        const today = await resolveToday(userId, args.today);
        return { proposals: await listProposals(userId, args.status ?? "pending", args.limit ?? 20, today) };
      }),
  );

  server.registerTool(
    "propose_change",
    {
      title: "Propose a plan change",
      description: PROPOSE_DESCRIPTION,
      inputSchema: {
        today: todayParam,
        title: z.string().min(1).max(120).describe("One line the runner sees on the proposal card, e.g. \"Easier Thursday\"."),
        reason: z.string().min(1).max(600).describe("Why: grounded in their runs, check-ins and plan."),
        changes: changesSchema.describe("The days to change: local_date and the new DaySpec."),
        deviation_reason: z.string().max(600).optional().describe("Required when the change breaks a convention rule (the error says which)."),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async (args) =>
      run("propose_change", args, async () => {
        const today = await resolveToday(userId, args.today);
        const proposal = await createProposal(
          userId,
          {
            source: "user_claude",
            kind: "adjust",
            title: args.title,
            reason: args.reason,
            changes: args.changes.map((c) => ({ local_date: c.local_date, spec: cleanDaySpec(c.day) })),
            deviation_reason: args.deviation_reason ?? null,
          },
          today,
        );
        return { today, note: "Pending: the runner applies or keeps it in the Mile A Day app.", proposal };
      }),
  );

  return server;
}

export const COACH_TOOL_NAMES = ["get_checkins", "get_plan", "get_profile", "get_runs", "list_proposals", "propose_change"];
