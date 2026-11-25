import Anthropic from "@anthropic-ai/sdk";
import { PostgresService } from "../DbService.js";
import { COACH_RULES_TEXT, DaySpec, OptionIntent } from "./engine.js";
import {
  addAnthropicSpend,
  anthropicBudgetExhausted,
  costUsd,
  getAiStatus,
  recordAiCall,
} from "./coachSettings.js";
import {
  RunPlanError,
  ServedProposal,
  coachBuildDay,
  coachEstimate,
  coachOptions,
  coachValidate,
  createProposal,
  getCoachContext,
  putCoachNotes,
} from "./runPlanService.js";

/**
 * The optional server-side AI Coach (ai_mode = 'anthropic'). Claude gets the
 * same tools the phone's Apple model uses: it reads computed numbers, asks
 * for options, validates, and SUBMITS PROPOSALS — it can never apply one.
 *
 * Haiku 5.5 (effort low) for check-ins, chat, notes and post-run summaries;
 * Sonnet 5.5 (effort medium) for plan builds, adjustments and weekly reviews.
 * Strict tools with `tool_choice: auto` (forced tool choice 400s on these
 * models). The shared rules prefix (system + tools) is prompt-cached. Every
 * call is logged with tokens and cost and added to the monthly counter, which
 * refuses new calls once it reaches COACH_ANTHROPIC_STOP_USD (default $48).
 */

const db = PostgresService.getInstance();

export const HAIKU = "claude-haiku-5-5";
export const SONNET = "claude-sonnet-5-5";
export const ANTHROPIC_KINDS = ["chat", "checkin", "adjust", "plan_build", "weekly_review", "post_run", "notes"] as const;
export type AnthropicKind = (typeof ANTHROPIC_KINDS)[number];
const MAX_TURNS = 8;

export function modelFor(kind: AnthropicKind): { model: string; effort: "low" | "medium" } {
  return kind === "plan_build" || kind === "adjust" || kind === "weekly_review" ? { model: SONNET, effort: "medium" } : { model: HAIKU, effort: "low" };
}

/** The subset of the SDK client we use (so the check can inject a mock). */
export interface MessagesClient {
  messages: { create(params: Anthropic.MessageCreateParamsNonStreaming): Promise<Anthropic.Message> };
}
let clientOverride: MessagesClient | null = null;
export function setAnthropicClientForTesting(c: MessagesClient | null): void {
  clientOverride = c;
}
let realClient: Anthropic | null = null;
function client(): MessagesClient {
  if (clientOverride) return clientOverride;
  realClient ??= new Anthropic();
  return realClient;
}

const SYSTEM = `You are Flamey, the running coach inside Mile A Day, an app about running (or walking) a mile every day.
You design and adjust this runner's plan through tools. Code computes every number; you choose among computed options, explain them, and write short, warm, plain notes.
Rules you must follow:
- Every change is a PROPOSAL the runner approves in the app. Use submit_proposal; nothing you do changes the plan directly.
- Never state a pace, distance, heart rate or time that a tool didn't give you.
- Before submitting, call validate. If a HARD rule fails, pick another option. If a convention is broken, give a one-sentence deviation_reason.
- Keep today's changes small (about +-10%); bigger changes go to later days.
- No medical, dosing, diet or calorie-deficit advice. Pain and illness are the runner's call; respond only through easier or shorter runs.
- Notes are 1-3 sentences, no emoji.
- If nothing should change, say so and submit nothing.

${COACH_RULES_TEXT}`;

const DAY_SPEC_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["kind", "distance_mi", "work_mi", "reps", "rep_mi", "rep_s", "recover_s", "pace_factor", "strides", "note"],
  properties: {
    kind: { type: "string", enum: ["easy", "long", "tempo", "intervals", "race", "calibration", "walk"] },
    distance_mi: { type: ["number", "null"] },
    work_mi: { type: ["number", "null"] },
    reps: { type: ["integer", "null"] },
    rep_mi: { type: ["number", "null"] },
    rep_s: { type: ["integer", "null"] },
    recover_s: { type: ["integer", "null"] },
    pace_factor: { type: ["number", "null"], description: "0.85-1.15 multiplier on the plan's paces; >1 slower" },
    strides: { type: ["boolean", "null"] },
    note: { type: ["string", "null"], description: "Flamey's note for the day (1-3 sentences)" },
  },
} as const;
const CHANGES_SCHEMA = {
  type: "array",
  items: { type: "object", additionalProperties: false, required: ["local_date", "after"], properties: { local_date: { type: "string" }, after: DAY_SPEC_SCHEMA } },
} as const;

export const COACH_TOOLS: Anthropic.Tool[] = [
  {
    name: "build_day",
    description: "Compute a full day (segments, paces, HR bands, distance) from a day spec, and check it against the rules. Saves nothing.",
    strict: true,
    input_schema: { type: "object", additionalProperties: false, required: ["local_date", "day"], properties: { local_date: { type: "string" }, day: DAY_SPEC_SCHEMA } } as any,
  },
  {
    name: "options",
    description: "Computed alternatives for one day that already pass the HARD rules. intent: easier, shorter, longer, harder, swap_walk, move_key, fit_time.",
    strict: true,
    input_schema: {
      type: "object",
      additionalProperties: false,
      required: ["local_date", "intent", "minutes", "to_date"],
      properties: {
        local_date: { type: "string" },
        intent: { type: "string", enum: ["easier", "shorter", "longer", "harder", "swap_walk", "move_key", "fit_time"] },
        minutes: { type: ["integer", "null"] },
        to_date: { type: ["string", "null"] },
      },
    } as any,
  },
  {
    name: "validate",
    description: "Dry-run a set of day changes against the HARD rules and conventions. Returns violations, deviations and the week totals.",
    strict: true,
    input_schema: { type: "object", additionalProperties: false, required: ["changes"], properties: { changes: CHANGES_SCHEMA } } as any,
  },
  {
    name: "estimate",
    description: "Race-time estimate from the runner's fitness for a distance (mile, 5k, 10k, half, marathon).",
    strict: true,
    input_schema: { type: "object", additionalProperties: false, required: ["distance"], properties: { distance: { type: "string", enum: ["mile", "5k", "10k", "half", "marathon"] } } } as any,
  },
  {
    name: "submit_proposal",
    description: "Submit a proposed change for the runner to Apply or Keep in the app. It is validated again; HARD-rule violations are rejected.",
    strict: true,
    input_schema: {
      type: "object",
      additionalProperties: false,
      required: ["kind", "title", "reason", "changes", "deviation_reason"],
      properties: {
        kind: { type: "string", enum: ["adjust", "missed_run", "return_from_break", "pace_update", "checkin", "walk_day_earned", "walk_day_needed", "post_run", "weekly_review", "plan_build"] },
        title: { type: "string", description: "Short, e.g. 'Easy 4 mi instead of 5 x 800m'" },
        reason: { type: "string", description: "One sentence why" },
        changes: CHANGES_SCHEMA,
        deviation_reason: { type: ["string", "null"] },
      },
    } as any,
  },
  {
    name: "write_notes",
    description: "Write Flamey's notes on upcoming days and summaries on completed runs. Text only; does not change the plan.",
    strict: true,
    input_schema: {
      type: "object",
      additionalProperties: false,
      required: ["notes", "grade_summaries"],
      properties: {
        notes: { type: "array", items: { type: "object", additionalProperties: false, required: ["local_date", "note"], properties: { local_date: { type: "string" }, note: { type: "string" } } } },
        grade_summaries: { type: "array", items: { type: "object", additionalProperties: false, required: ["local_date", "summary"], properties: { local_date: { type: "string" }, summary: { type: "string" } } } },
      },
    } as any,
  },
];
// Cache the shared prefix: render order is tools → system, so the breakpoint on
// the system block covers both.
const SYSTEM_BLOCKS: Anthropic.TextBlockParam[] = [{ type: "text", text: SYSTEM, cache_control: { type: "ephemeral" } }];

const strip = <T extends Record<string, unknown>>(o: T) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== null)) as Partial<T>;
const cleanSpec = (d: any): DaySpec => strip(d ?? {}) as unknown as DaySpec;

async function runTool(userId: string, today: string, name: string, input: any, proposals: ServedProposal[], notes: { n: number }, kind: AnthropicKind): Promise<unknown> {
  switch (name) {
    case "build_day":
      return coachBuildDay(userId, today, input.local_date, cleanSpec(input.day));
    case "options":
      return coachOptions(userId, today, input.local_date, input.intent as OptionIntent, { minutes: input.minutes ?? undefined, to_date: input.to_date ?? undefined });
    case "validate":
      return coachValidate(userId, today, (input.changes ?? []).map((c: any) => ({ local_date: c.local_date, after: cleanSpec(c.after) })));
    case "estimate":
      return coachEstimate(userId, input.distance, null);
    case "submit_proposal": {
      const p = await createProposal(userId, { source: "anthropic", kind: input.kind ?? (kind === "checkin" ? "checkin" : "adjust"), title: String(input.title ?? ""), reason: String(input.reason ?? ""), changes: (input.changes ?? []).map((c: any) => ({ local_date: c.local_date, spec: cleanSpec(c.after) })), deviation_reason: input.deviation_reason ?? null }, today);
      proposals.push(p);
      return { ok: true, proposal_id: p.id, checks: p.checks };
    }
    case "write_notes": {
      const r = await putCoachNotes(userId, today, "anthropic", input.notes ?? [], input.grade_summaries ?? []);
      notes.n += r.updated;
      return r;
    }
    default:
      throw new RunPlanError("unknown_tool", 400);
  }
}

export interface AnthropicRunInput {
  today: string;
  kind: AnthropicKind;
  message?: string | null;
  checkin_id?: string | null;
  trigger?: string | null;
}

export async function runAnthropicCoach(userId: string, input: AnthropicRunInput): Promise<{ reply: string | null; proposals: ServedProposal[]; notes_updated: number; call_id: string | null }> {
  if (!ANTHROPIC_KINDS.includes(input.kind)) throw new RunPlanError("invalid_source", 400, { field: "kind" });
  const status = await getAiStatus(userId);
  if (status.ai_mode !== "anthropic") throw new RunPlanError("ai_unavailable", 503, { reason: "mode_not_anthropic" });
  if (status.reason === "anthropic_consent_required") throw new RunPlanError("consent_required", 403);
  if (status.effective !== "anthropic") throw new RunPlanError("ai_unavailable", 503, { reason: status.reason ?? "global_off" });
  if (await anthropicBudgetExhausted()) throw new RunPlanError("ai_unavailable", 503, { reason: "anthropic_budget_exhausted" });

  const { model, effort } = modelFor(input.kind);
  const ctx = await getCoachContext(userId, input.today, 14, input.kind === "plan_build" || input.kind === "weekly_review" ? 21 : 14);
  let checkin: unknown = null;
  if (input.checkin_id) {
    const r = await db.query(`SELECT local_date::text AS local_date, time_available_min, energy, soreness, go_further_mi, text FROM run_plan_checkins WHERE id = $1 AND user_id = $2`, [input.checkin_id, userId]);
    checkin = r[0] ?? null;
  }
  const { rules: _r, ...ctxNoRules } = ctx;
  const task = {
    chat: "The runner wrote a message. Answer it in 1-4 sentences. Propose a change only if they ask for one or it clearly helps.",
    checkin: "The runner checked in before today's run. Decide whether today's run should change; if so submit one small proposal for today.",
    adjust: "Review the last two weeks against the plan (missed runs, pace vs target, fatigue signals) and propose any adjustments for the coming days.",
    plan_build: "The plan was just built by the formula. Review it for this runner and their notes; propose changes only where they clearly help, and write notes for the first week.",
    weekly_review: "Weekly review: summarize the week in 2-3 sentences and propose next week's adjustments if needed.",
    post_run: "The runner just finished a run. Write the grade summary for it (write_notes) and propose changes for the coming days only if needed.",
    notes: "Write Flamey's notes for the next 7 days (write_notes).",
  }[input.kind];
  const userText = `${task}\n\nRunner context (JSON):\n${JSON.stringify(ctxNoRules)}${checkin ? `\n\nCheck-in:\n${JSON.stringify(checkin)}` : ""}${input.message ? `\n\nRunner's message:\n${input.message.slice(0, 2000)}` : ""}`;
  const messages: Anthropic.MessageParam[] = [{ role: "user", content: userText }];
  const proposals: ServedProposal[] = [];
  const notes = { n: 0 };
  const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
  const toolLog: { name: string; ok: boolean }[] = [];
  let reply: string | null = null;
  let error: string | null = null;
  let cost = 0;
  const started = Date.now();
  try {
    for (let turn = 0; turn < MAX_TURNS; turn++) {
      if (turn > 0 && (await anthropicBudgetExhausted())) {
        error = "budget_exhausted_mid_call";
        break;
      }
      const res = await client().messages.create({
        model,
        max_tokens: 16000,
        system: SYSTEM_BLOCKS,
        tools: COACH_TOOLS,
        tool_choice: { type: "auto" },
        output_config: { effort },
        messages,
      });
      const u = res.usage;
      const callUsage = { input: u.input_tokens ?? 0, output: u.output_tokens ?? 0, cacheRead: u.cache_read_input_tokens ?? 0, cacheWrite: u.cache_creation_input_tokens ?? 0 };
      usage.input += callUsage.input;
      usage.output += callUsage.output;
      usage.cacheRead += callUsage.cacheRead;
      usage.cacheWrite += callUsage.cacheWrite;
      const c = costUsd(model, callUsage);
      cost += c;
      await addAnthropicSpend(c);
      if (res.stop_reason === "refusal") {
        error = "refusal";
        break;
      }
      const text = res.content.filter((b): b is Anthropic.TextBlock => b.type === "text").map((b) => b.text).join("\n").trim();
      if (text) reply = text;
      if (res.stop_reason !== "tool_use") break;
      messages.push({ role: "assistant", content: res.content });
      const results: Anthropic.ToolResultBlockParam[] = [];
      for (const block of res.content) {
        if (block.type !== "tool_use") continue;
        try {
          const out = await runTool(userId, input.today, block.name, block.input, proposals, notes, input.kind);
          toolLog.push({ name: block.name, ok: true });
          results.push({ type: "tool_result", tool_use_id: block.id, content: JSON.stringify(out).slice(0, 60_000) });
        } catch (e: any) {
          toolLog.push({ name: block.name, ok: false });
          const detail = e instanceof RunPlanError ? { error: e.code, ...e.extra } : { error: "tool_failed" };
          results.push({ type: "tool_result", tool_use_id: block.id, content: JSON.stringify(detail), is_error: true });
        }
      }
      messages.push({ role: "user", content: results });
    }
  } catch (e: any) {
    error = e instanceof Anthropic.APIError ? `api_${e.status ?? "error"}` : e instanceof RunPlanError ? e.code : "provider_error";
    console.error("[coach] Anthropic call failed:", e?.message ?? e);
  }
  const callId = await recordAiCall(userId, {
    provider: "anthropic",
    kind: input.kind === "checkin" ? "checkin" : input.kind,
    trigger: input.trigger ?? (input.kind === "chat" ? "chat" : input.kind === "checkin" ? "checkin" : null),
    model,
    started_at: new Date(started).toISOString(),
    latency_ms: Date.now() - started,
    input: userText,
    output: JSON.stringify({ reply, tools: toolLog }),
    tool_calls: toolLog,
    tokens_in: usage.input + usage.cacheRead + usage.cacheWrite,
    tokens_out: usage.output,
    tokens_cached: usage.cacheRead,
    tokens_cache_write: usage.cacheWrite,
    cost_usd: Math.round(cost * 1e6) / 1e6,
    error,
    proposal_ids: proposals.map((p) => p.id),
  });
  if (error && !reply && !proposals.length) throw new RunPlanError("ai_unavailable", 503, { reason: "provider_error", call_id: callId });
  return { reply, proposals, notes_updated: notes.n, call_id: callId };
}

export const ANTHROPIC_BACKGROUND_MIN_HOURS = 6;
/**
 * Background adjust pass for Anthropic users (after a run, nightly): at most
 * one per user per 6 hours, claimed on coach_settings.last_anthropic_run_at.
 * Fire-and-forget; never throws.
 */
export async function maybeRunAnthropicInBackground(userId: string, today: string, trigger: string): Promise<boolean> {
  try {
    const st = await getAiStatus(userId);
    if (st.effective !== "anthropic") return false;
    const claimed = await db.query(
      `UPDATE coach_settings SET last_anthropic_run_at = now()
        WHERE user_id = $1 AND (last_anthropic_run_at IS NULL OR last_anthropic_run_at < now() - make_interval(hours => $2)) RETURNING 1`,
      [userId, ANTHROPIC_BACKGROUND_MIN_HOURS],
    );
    if (!claimed.length) return false;
    await runAnthropicCoach(userId, { today, kind: trigger === "after_run" ? "post_run" : "adjust", trigger });
    return true;
  } catch (e: any) {
    console.error("[coach] background Anthropic pass failed:", e?.code ?? e?.message ?? e);
    return false;
  }
}
