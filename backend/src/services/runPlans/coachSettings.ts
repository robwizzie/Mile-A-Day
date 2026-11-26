import { PostgresService } from "../DbService.js";
import { isPlusActive } from "../plusService.js";

/**
 * AI Coach access, call log and the Anthropic spend counter.
 *
 * - Per user: `coach_settings.ai_mode` (no row = 'apple', the default for
 *   every Plus member), set from the admin site; `user_opt_out` is the
 *   member's own "formula plan only" switch.
 * - Global: `app_settings['coach']` = { ai_enabled, anthropic_enabled }, plus
 *   env kill switch `COACH_AI_DISABLED=1`.
 * - Anthropic runs only with `ANTHROPIC_API_KEY` set, the user's consent, and
 *   the month's spend under `COACH_ANTHROPIC_STOP_USD` (default 48).
 */

const db = PostgresService.getInstance();

export const AI_MODES = ["off", "apple", "anthropic"] as const;
export type AiMode = (typeof AI_MODES)[number];
export type EffectiveProvider = "apple" | "anthropic" | "formula";
export type AiReason =
  | "global_off"
  | "user_opt_out"
  | "anthropic_not_configured"
  | "anthropic_budget_exhausted"
  | "anthropic_consent_required"
  | "not_plus"
  | "mode_off";

export interface AiStatus {
  ai_mode: AiMode;
  global_enabled: boolean;
  effective: EffectiveProvider;
  reason: AiReason | null;
  anthropic_consent_at: string | null;
  user_opt_out: boolean;
}

export const ANTHROPIC_CAP_USD = () => Number(process.env.COACH_ANTHROPIC_CAP_USD ?? 50);
export const ANTHROPIC_STOP_USD = () => Number(process.env.COACH_ANTHROPIC_STOP_USD ?? 48);
export const ANTHROPIC_WARN_USD = (): [number, number] => {
  const [a, b] = (process.env.COACH_ANTHROPIC_WARN_USD ?? "25,40").split(",").map(Number);
  return [a || 25, b || 40];
};
export const anthropicConfigured = () => Boolean(process.env.ANTHROPIC_API_KEY);

export interface GlobalCoachSettings {
  ai_enabled: boolean;
  anthropic_enabled: boolean;
}
export async function getGlobalCoachSettings(): Promise<GlobalCoachSettings> {
  const rows = await db.query<{ value: Partial<GlobalCoachSettings> }>(`SELECT value FROM app_settings WHERE key = 'coach'`);
  const v = rows[0]?.value ?? {};
  return {
    ai_enabled: process.env.COACH_AI_DISABLED === "1" ? false : v.ai_enabled !== false,
    anthropic_enabled: v.anthropic_enabled !== false,
  };
}
export async function setGlobalCoachSettings(patch: Partial<GlobalCoachSettings>, adminId: string): Promise<GlobalCoachSettings> {
  const cur = await getGlobalCoachSettings();
  const next = {
    ai_enabled: patch.ai_enabled ?? cur.ai_enabled,
    anthropic_enabled: patch.anthropic_enabled ?? cur.anthropic_enabled,
  };
  await db.query(
    `INSERT INTO app_settings (key, value, updated_by, updated_at) VALUES ('coach', $1::jsonb, $2, now())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_by = EXCLUDED.updated_by, updated_at = now()`,
    [JSON.stringify(next), adminId],
  );
  return getGlobalCoachSettings();
}

interface SettingsRow {
  ai_mode: AiMode;
  user_opt_out: boolean;
  anthropic_consent_at: string | null;
  last_anthropic_run_at: string | null;
}
export async function getUserCoachSettings(userId: string): Promise<SettingsRow> {
  const rows = await db.query<SettingsRow>(
    `SELECT ai_mode, user_opt_out, anthropic_consent_at, last_anthropic_run_at FROM coach_settings WHERE user_id = $1`,
    [userId],
  );
  return rows[0] ?? { ai_mode: "apple", user_opt_out: false, anthropic_consent_at: null, last_anthropic_run_at: null };
}

export async function setUserAiMode(userId: string, mode: AiMode, adminId: string | null): Promise<AiMode> {
  if (!AI_MODES.includes(mode)) throw new Error("invalid_ai_mode");
  await db.query(
    `INSERT INTO coach_settings (user_id, ai_mode, updated_by, updated_at) VALUES ($1, $2, $3, now())
     ON CONFLICT (user_id) DO UPDATE SET ai_mode = EXCLUDED.ai_mode, updated_by = EXCLUDED.updated_by, updated_at = now()`,
    [userId, mode, adminId],
  );
  return mode;
}
export async function setUserOptOut(userId: string, optOut: boolean): Promise<void> {
  await db.query(
    `INSERT INTO coach_settings (user_id, user_opt_out, updated_at) VALUES ($1, $2, now())
     ON CONFLICT (user_id) DO UPDATE SET user_opt_out = EXCLUDED.user_opt_out, updated_at = now()`,
    [userId, optOut],
  );
}
export async function setAnthropicConsent(userId: string, accepted: boolean): Promise<void> {
  await db.query(
    `INSERT INTO coach_settings (user_id, anthropic_consent_at, updated_at) VALUES ($1, CASE WHEN $2::boolean THEN now() END, now())
     ON CONFLICT (user_id) DO UPDATE SET anthropic_consent_at = CASE WHEN $2::boolean THEN COALESCE(coach_settings.anthropic_consent_at, now()) END, updated_at = now()`,
    [userId, accepted],
  );
}

/** Which provider the app (or server) must use for this user right now. */
export async function getAiStatus(userId: string, plus?: boolean): Promise<AiStatus> {
  const [s, g, isPlus] = await Promise.all([getUserCoachSettings(userId), getGlobalCoachSettings(), plus ?? isPlusActive(userId)]);
  const base = { ai_mode: s.ai_mode, global_enabled: g.ai_enabled, anthropic_consent_at: s.anthropic_consent_at, user_opt_out: s.user_opt_out };
  const formula = (reason: AiReason | null): AiStatus => ({ ...base, effective: "formula", reason });
  if (!isPlus) return formula("not_plus");
  if (s.ai_mode === "off") return formula(null);
  if (!g.ai_enabled) return formula("global_off");
  if (s.user_opt_out) return formula("user_opt_out");
  if (s.ai_mode === "apple") return { ...base, effective: "apple", reason: null };
  if (!g.anthropic_enabled || !anthropicConfigured()) return formula("anthropic_not_configured");
  if (!s.anthropic_consent_at) return formula("anthropic_consent_required");
  if (await anthropicBudgetExhausted()) return formula("anthropic_budget_exhausted");
  return { ...base, effective: "anthropic", reason: null };
}

// ─── Anthropic spend ─────────────────────────────────────────────────────

/** USD per 1M tokens (Anthropic first-party): input, output, cache read, 5-min cache write (1.25×). */
export const MODEL_PRICES: Record<string, { in: number; out: number; cacheRead: number; cacheWrite: number }> = {
  "claude-haiku-5-5": { in: 0.1, out: 0.5, cacheRead: 0.01, cacheWrite: 0.125 },
  "claude-sonnet-5-5": { in: 2, out: 10, cacheRead: 0.1, cacheWrite: 2.5 },
};
export function costUsd(model: string, u: { input: number; output: number; cacheRead: number; cacheWrite: number }): number {
  const p = MODEL_PRICES[model] ?? MODEL_PRICES["claude-sonnet-5-5"];
  return (u.input * p.in + u.output * p.out + u.cacheRead * p.cacheRead + u.cacheWrite * p.cacheWrite) / 1_000_000;
}

export const currentMonth = (now = new Date()) => now.toISOString().slice(0, 7);

export async function monthSpend(month = currentMonth()): Promise<{ spent_usd: number; calls: number; stopped_at: string | null }> {
  const rows = await db.query<{ spent_usd: number; calls: number; stopped_at: string | null }>(
    `SELECT spent_usd, calls, stopped_at FROM coach_spend_monthly WHERE month = $1`,
    [month],
  );
  return rows[0] ? { spent_usd: Number(rows[0].spent_usd), calls: rows[0].calls, stopped_at: rows[0].stopped_at } : { spent_usd: 0, calls: 0, stopped_at: null };
}
export async function anthropicBudgetExhausted(month = currentMonth()): Promise<boolean> {
  return (await monthSpend(month)).spent_usd >= ANTHROPIC_STOP_USD();
}

/** Add one call's cost; stamps the warn/stop thresholds once each. Returns the new month total. */
export async function addAnthropicSpend(cost: number, month = currentMonth()): Promise<number> {
  const [low, high] = ANTHROPIC_WARN_USD();
  const rows = await db.query<{ spent_usd: number; warned_low_at: string | null; warned_high_at: string | null; stopped_at: string | null }>(
    `INSERT INTO coach_spend_monthly (month, spent_usd, calls, updated_at) VALUES ($1, $2, 1, now())
     ON CONFLICT (month) DO UPDATE SET spent_usd = coach_spend_monthly.spent_usd + EXCLUDED.spent_usd,
       calls = coach_spend_monthly.calls + 1, updated_at = now()
     RETURNING spent_usd, warned_low_at, warned_high_at, stopped_at`,
    [month, cost],
  );
  const r = rows[0];
  const total = Number(r.spent_usd);
  const stamp = async (col: string) => db.query(`UPDATE coach_spend_monthly SET ${col} = now() WHERE month = $1 AND ${col} IS NULL`, [month]);
  if (total >= low && !r.warned_low_at) {
    await stamp("warned_low_at");
    console.warn(`[coach] Anthropic spend ${month} passed $${low}: $${total.toFixed(2)}`);
  }
  if (total >= high && !r.warned_high_at) {
    await stamp("warned_high_at");
    console.warn(`[coach] Anthropic spend ${month} passed $${high}: $${total.toFixed(2)}`);
  }
  if (total >= ANTHROPIC_STOP_USD() && !r.stopped_at) {
    await stamp("stopped_at");
    console.warn(`[coach] Anthropic spend ${month} hit the $${ANTHROPIC_STOP_USD()} stop; AI Coach falls back to the formula plan.`);
  }
  return total;
}

// ─── AI call log (90-day retention, admins only) ─────────────────────────

export const AI_CALL_RETENTION_DAYS = 90;
export const AI_CALL_KINDS = ["plan_build", "adjust", "checkin", "chat", "notes", "post_run", "weekly_review"] as const;
export const AI_CALL_TRIGGERS = ["after_run", "first_open", "nightly", "checkin", "chat", "setup"] as const;
const MAX_TEXT = 64 * 1024;

export interface AiCallInput {
  provider: "apple" | "anthropic";
  kind: string;
  trigger?: string | null;
  model?: string | null;
  client_call_id?: string | null;
  started_at?: string | null;
  latency_ms?: number | null;
  input?: string | null;
  output?: string | null;
  tool_calls?: unknown;
  tokens_in?: number | null;
  tokens_out?: number | null;
  tokens_cached?: number | null;
  tokens_cache_write?: number | null;
  cost_usd?: number | null;
  error?: string | null;
  daily_limit_hit?: boolean;
  proposal_ids?: string[];
}

export async function recordAiCall(userId: string, c: AiCallInput): Promise<string | null> {
  const rows = await db.query<{ id: string }>(
    `INSERT INTO coach_ai_calls (user_id, provider, kind, trigger, model, client_call_id, started_at, latency_ms, input, output,
        tool_calls, tokens_in, tokens_out, tokens_cached, tokens_cache_write, cost_usd, error, daily_limit_hit, proposal_ids)
     VALUES ($1, $2, $3, $4, $5, $6, $7::timestamptz, $8, $9, $10, $11::jsonb, $12, $13, $14, $15, $16, $17, $18, $19::jsonb)
     ON CONFLICT (user_id, client_call_id) WHERE client_call_id IS NOT NULL DO NOTHING
     RETURNING id`,
    [
      userId, c.provider, c.kind, c.trigger ?? null, c.model ?? null, c.client_call_id ?? null, c.started_at ?? null,
      c.latency_ms ?? null, c.input?.slice(0, MAX_TEXT) ?? null, c.output?.slice(0, MAX_TEXT) ?? null,
      c.tool_calls == null ? null : JSON.stringify(c.tool_calls), c.tokens_in ?? null, c.tokens_out ?? null,
      c.tokens_cached ?? null, c.tokens_cache_write ?? null, c.cost_usd ?? null, c.error?.slice(0, 2000) ?? null,
      Boolean(c.daily_limit_hit), JSON.stringify(c.proposal_ids ?? []),
    ],
  );
  return rows[0]?.id ?? null;
}

export class CallLogError extends Error {}
const intOrNull = (v: unknown, max: number) => {
  if (v == null) return null;
  const n = Number(v);
  if (!Number.isInteger(n) || n < 0 || n > max) throw new CallLogError("invalid_call_log");
  return n;
};
const strOrNull = (v: unknown, max: number) => {
  if (v == null) return null;
  if (typeof v !== "string") throw new CallLogError("invalid_call_log");
  if (v.length > max) throw new CallLogError("call_log_too_large");
  return v;
};

/** The phone's Apple-model call log upload (≤ 20 per request, idempotent on client_call_id). */
export async function uploadAiCalls(userId: string, raw: unknown): Promise<{ accepted: number; ids: string[] }> {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 20) throw new CallLogError("invalid_call_log");
  const parsed: AiCallInput[] = raw.map((c: any) => {
    if (!c || c.provider !== "apple") throw new CallLogError("invalid_call_log");
    if (!AI_CALL_KINDS.includes(c.kind)) throw new CallLogError("invalid_call_log");
    if (c.trigger != null && !AI_CALL_TRIGGERS.includes(c.trigger)) throw new CallLogError("invalid_call_log");
    if (c.started_at != null && Number.isNaN(Date.parse(c.started_at))) throw new CallLogError("invalid_call_log");
    const ids = c.proposal_ids == null ? [] : c.proposal_ids;
    if (!Array.isArray(ids) || ids.length > 20 || ids.some((x: unknown) => typeof x !== "string")) throw new CallLogError("invalid_call_log");
    return {
      provider: "apple",
      kind: c.kind,
      trigger: c.trigger ?? null,
      model: strOrNull(c.model, 80) ?? "apple-pcc",
      client_call_id: strOrNull(c.client_call_id, 80),
      started_at: c.started_at ?? null,
      latency_ms: intOrNull(c.latency_ms, 600_000),
      input: strOrNull(c.input, MAX_TEXT),
      output: strOrNull(c.output, MAX_TEXT),
      tool_calls: Array.isArray(c.tool_calls) ? c.tool_calls.slice(0, 50) : null,
      tokens_in: intOrNull(c.tokens_in, 10_000_000),
      tokens_out: intOrNull(c.tokens_out, 10_000_000),
      error: strOrNull(c.error, 2000),
      daily_limit_hit: Boolean(c.daily_limit_hit),
      proposal_ids: ids,
    };
  });
  const ids: string[] = [];
  for (const c of parsed) {
    const id = await recordAiCall(userId, c);
    if (id) ids.push(id);
  }
  return { accepted: ids.length, ids };
}

/** Delete AI call logs older than 90 days (health-derived data; spec §11 privacy). */
export async function sweepAiCallLogs(retentionDays = AI_CALL_RETENTION_DAYS): Promise<number> {
  const rows = await db.query<{ n: number }>(
    `WITH d AS (DELETE FROM coach_ai_calls WHERE created_at < now() - make_interval(days => $1) RETURNING 1)
     SELECT COUNT(*)::int AS n FROM d`,
    [retentionDays],
  );
  return rows[0]?.n ?? 0;
}
