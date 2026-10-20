/**
 * Coach MCP tools. Every tool is scoped to the signed-in user (the token's
 * user id; no tool takes a user argument) and goes through the Run Plans
 * service, so every number still comes from the engine and every change is
 * capped by it. No SQL, no other users, nothing outside the plan.
 */
import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { AuthInfo } from "@modelcontextprotocol/sdk/server/auth/types.js";
import { PostgresService } from "../services/DbService.js";
import { userTodaySql } from "../services/streakFeatureCore.js";
import {
  ACTIONS,
  DAY_KINDS,
  HARDER_MAX_PCT,
  HARDER_MAX_REPS,
  WEEK_TOTAL_SLACK_MI,
  addDays,
  isIsoDate,
} from "../services/runPlans/engine.js";
import {
  RunPlanError,
  createProposal,
  getCurrentPlan,
  getPlanDays,
  getProfile,
  getRuns,
  listCheckins,
  listProposals,
} from "../services/runPlans/runPlanService.js";
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
  const rows = await db.query<{ today: string }>(
    `SELECT (${userTodaySql("u")})::text AS today FROM users u WHERE u.user_id = $1`,
    [userId],
  );
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
    if (err.code === "action_not_possible") {
      return fail(`action_not_possible (422): ${String(err.extra.cap_note ?? "the plan's rules don't allow that")}`);
    }
    return fail(`${err.code} (${err.status})${Object.keys(err.extra).length ? ` ${JSON.stringify(err.extra)}` : ""}`);
  }
  console.error("[coach-mcp] tool failed", err);
  return fail("Something went wrong on the Mile A Day side. Try again in a moment.");
}

export const SERVER_INSTRUCTIONS =
  "You are coaching ONE Mile A Day runner: the person who signed in. You can read their run plan, runs and " +
  "check-ins, and PROPOSE changes to the plan. You cannot see or change anything else, or anyone else.\n" +
  "Rules of the plan:\n" +
  "- The plan engine sets every number (distances, paces, intervals). You choose an ACTION; the engine applies it " +
  "and clamps it to the caps. You never type paces.\n" +
  "- Mile A Day is a daily streak: every day is at least 1 mile, including rest days (a 'streak' day).\n" +
  "- A proposal is PENDING until the runner taps Swap/Keep in the app, unless they turned on auto-apply for Claude " +
  "(then propose_change says applied=true). Say which happened.\n" +
  "- Dates are the runner's LOCAL YYYY-MM-DD. Pass `today` (their local date) when you know it.\n" +
  "- Units: miles; paces and durations in seconds (pace = seconds per mile).\n" +
  "- If they report pain or injury, suggest just_mile or easier and seeing a doctor; never push through pain.\n" +
  "Start with get_profile and get_plan; look at get_runs and get_checkins before proposing anything.";

const PROPOSE_DESCRIPTION =
  "Propose ONE change to the runner's plan. The engine computes the new day(s) and enforces the caps; you pick the " +
  "action and explain why.\n" +
  "Actions (params):\n" +
  "- easier {local_date?}: ease that day (less volume, gentler paces). local_date defaults to today, or tomorrow if " +
  "today's run is already done — same default for shorter/just_mile/harder.\n" +
  "- shorter {local_date?}: cut the day's distance (never below 1 mi).\n" +
  "- just_mile {local_date?, soften_next_hard?}: make the day just the daily streak mile; soften_next_hard=true also " +
  "eases the next hard session.\n" +
  `- harder {local_date?, reps?, percent?}: intervals get +reps (max +${HARDER_MAX_REPS}); other days +percent ` +
  `distance (5–${HARDER_MAX_PCT * 100}, default 10). Also capped by the runner's longest-run limit.\n` +
  "- swap_hard_today {}: swap today's hard session with an easier day later this week.\n" +
  "- rest_tomorrow {}: make tomorrow just the streak mile (still a mile).\n" +
  "- move {from, to}: swap two plan days (both today or later).\n" +
  `- set_day {local_date, kind, distance_mi, segments?, note?}: rewrite one day. kind ∈ ${DAY_KINDS.join(" | ")}. ` +
  `distance_mi is clamped to ≥ 1 mi, ≤ the day's planned distance +${HARDER_MAX_PCT * 100}% (or +0.5 mi), and ≤ the ` +
  "longest-run limit. segments (optional) = [{kind: warmup|work|recover|cooldown|steady, distance_mi?, duration_s?, " +
  "target_pace_s?, rep?, reps?}] and must add up to distance_mi (±0.05) or the engine builds its own.\n" +
  `Plan-wide caps: a week's total after a swap/move/set stays ≤ its planned total + ${WEEK_TOTAL_SLACK_MI} mi; never ` +
  "two hard days (intervals, tempo, long, race_test) back to back while the plan has ≤ 3 hard days a week; days " +
  "already done or in the past don't change.\n" +
  "Returns {proposal, applied}: proposal.changes lists each day before/after; proposal.cap_note says what was " +
  "clamped. applied=false means it waits for the runner's approval in the app (the default); applied=true means " +
  "they enabled auto-apply. An impossible request returns an error with the reason (cap_note) — don't retry the " +
  "same thing. Make one well-explained proposal rather than many.";

export function buildCoachServer(auth: AuthInfo): McpServer {
  const userId = String(auth.extra?.userId);
  const grantId = String(auth.extra?.grantId);
  const server = new McpServer({ name: "mile-a-day-coach", version: "1.0.0" }, { instructions: SERVER_INSTRUCTIONS });

  /** Run a tool body with the audit row and uniform error replies. */
  const run = async (tool: string, args: unknown, body: () => Promise<unknown>): Promise<Reply> => {
    const t0 = Date.now();
    try {
      const out = await body();
      await recordToolCall({ userId, grantId, tool, args, outcome: "ok", detail: null, durationMs: Date.now() - t0 });
      return json(out);
    } catch (err) {
      const reply = errorReply(err);
      await recordToolCall({
        userId, grantId, tool, args, outcome: "error", detail: reply.content[0].text, durationMs: Date.now() - t0,
      });
      return reply;
    }
  };

  const read = { readOnlyHint: true, openWorldHint: false } as const;

  server.registerTool(
    "get_profile",
    {
      title: "Runner profile",
      description:
        "The runner's plan settings and fitness: goals, effort (1 Easy does it · 2 Steady · 3 Push · 4 All in), hard " +
        "days per week, whether every day's streak mile must be RUN, finish_by, auto-apply, plus the baseline the plan " +
        "was built from and their current fitness (best mile all-time and last 90 days, best ~5K, weekly miles, " +
        "longest recent run, easy pace, walk-heavy flag) and goal checkpoints. plan is null without an active plan.",
      inputSchema: { today: todayParam },
      annotations: read,
    },
    async (args) =>
      run("get_profile", args, async () => {
        const today = await resolveToday(userId, args.today);
        return { today, ...(await getProfile(userId, today)) };
      }),
  );

  server.registerTool(
    "get_plan",
    {
      title: "Plan days",
      description:
        "Plan days with kind, title, distance_mi, segments, target_pace_s, note, derived status (done | partial | " +
        "missed | today | planned), completion (workouts, miles, pace), whether it was moved or changed and by whom " +
        "(source: engine | flamey | claude | user). Only the current and next week are materialized; earlier days " +
        "exist once they were. Without from/to: the current overview (today, this and next week, week total, " +
        "checkpoints, pending proposals). With from/to (≤ 62 days): just those days.",
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
          return { today, from, to, days: await getPlanDays(userId, from, to, today) };
        }
        const cur = await getCurrentPlan(userId, today);
        if (!cur.plan) throw new RunPlanError("no_active_plan", 404);
        return {
          today,
          plan: cur.plan,
          today_day: cur.today,
          week_total_mi: cur.week_total_mi,
          week_done_mi: cur.week_done_mi,
          days: cur.days,
          checkpoints: cur.checkpoints,
          pending_proposals: cur.pending_proposals,
          warning: cur.warning,
        };
      }),
  );

  server.registerTool(
    "get_runs",
    {
      title: "Runs",
      description:
        "The runner's counted runs in [from, to] (≤ 120 days; default the last 28 days): distance, duration, moving " +
        "time, average pace (s/mi), walk_fraction (share of distance slower than a 15:00 mile), indoor flag and per-mile " +
        "splits. include_walks adds walking workouts.",
      inputSchema: {
        today: todayParam,
        from: date().optional(),
        to: date().optional(),
        include_walks: z.boolean().optional(),
      },
      annotations: read,
    },
    async (args) =>
      run("get_runs", args, async () => {
        checkDate("from", args.from);
        checkDate("to", args.to);
        const today = await resolveToday(userId, args.today);
        const to = args.to ?? today;
        const from = args.from ?? addDays(to, -27);
        return { from, to, runs: await getRuns(userId, from, to, { includeWalks: args.include_walks === true }) };
      }),
  );

  server.registerTool(
    "get_checkins",
    {
      title: "Check-ins",
      description:
        "How the runner said they felt, newest first: feeling (tired | sore | normal | great), optional message, " +
        "pain_flag. Default range: the last 30 days (≤ 366).",
      inputSchema: { today: todayParam, from: date().optional(), to: date().optional() },
      annotations: read,
    },
    async (args) =>
      run("get_checkins", args, async () => {
        checkDate("from", args.from);
        checkDate("to", args.to);
        const today = await resolveToday(userId, args.today);
        const to = args.to ?? today;
        const from = args.from ?? addDays(to, -29);
        return { from, to, checkins: await listCheckins(userId, from, to) };
      }),
  );

  server.registerTool(
    "list_proposals",
    {
      title: "Proposals",
      description:
        "Change proposals on the active plan, newest first, from any coach (flamey = the in-app coach, claude = you, " +
        "engine): status pending | applied | declined | expired, with each day's before/after. Check this before " +
        "proposing so you don't repeat one the runner already declined.",
      inputSchema: {
        status: z.enum(["pending", "applied", "declined", "expired"]).optional(),
        source: z.enum(["flamey", "claude", "engine"]).optional(),
        limit: z.number().int().min(1).max(100).optional(),
      },
      annotations: read,
    },
    async (args) =>
      run("list_proposals", args, async () => ({
        proposals: await listProposals(userId, { status: args.status, source: args.source, limit: args.limit ?? 20 }),
      })),
  );

  server.registerTool(
    "propose_change",
    {
      title: "Propose a plan change",
      description: PROPOSE_DESCRIPTION,
      inputSchema: {
        today: todayParam,
        action: z.enum(ACTIONS),
        params: z
          .object({
            local_date: date().optional(),
            from: date().optional(),
            to: date().optional(),
            reps: z.number().int().min(1).max(10).optional(),
            percent: z.number().min(1).max(100).optional(),
            soften_next_hard: z.boolean().optional(),
            kind: z.enum(DAY_KINDS).optional(),
            distance_mi: z.number().min(0).max(50).optional(),
            segments: z.array(z.record(z.string(), z.unknown())).max(60).optional(),
            note: z.string().max(280).optional(),
          })
          .optional()
          .describe("Only the params the action uses (see the list above)."),
        summary: z.string().min(1).max(120).describe("One line the runner sees on the proposal card."),
        rationale: z.string().min(1).max(2000).describe("Why: grounded in their runs, check-ins and plan."),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async (args) =>
      run("propose_change", args, async () => {
        const today = await resolveToday(userId, args.today);
        const proposal = await createProposal(
          userId,
          today,
          { action: args.action, params: args.params ?? {}, summary: args.summary, rationale: args.rationale },
          "claude",
        );
        return {
          today,
          applied: proposal.status === "applied",
          note:
            proposal.status === "applied"
              ? "Applied: the runner turned on auto-apply for Claude."
              : "Pending: the runner approves or declines it in the app.",
          proposal,
        };
      }),
  );

  return server;
}
