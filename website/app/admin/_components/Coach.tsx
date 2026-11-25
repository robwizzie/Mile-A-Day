"use client";

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import {
  Card,
  Chip,
  fmt,
  fmtDate,
  fmtDateTime,
  getData,
  Loading,
  MAD_RED,
  MAD_SUCCESS,
  MAD_WARNING,
  patchData,
  PANEL_BACKGROUND,
  putData,
  relativeDay,
  Section,
  SegmentedControl,
  SERIES,
  STACK_SECTIONS,
  StatCard,
  TILE,
} from "./lib";
import { StackedDayBars } from "./charts";
import { MAD_ERROR } from "./theme";

// ─── Types (mirror backend/src/services/runPlans/adminCoachService.ts) ──

export type AiMode = "off" | "apple" | "anthropic";
type Provider = "apple" | "anthropic";

type Settings = { ai_enabled: boolean; anthropic_enabled: boolean };

type Usage = {
  days: number;
  by_day: {
    date: string;
    provider: Provider;
    kind: string;
    calls: number;
    errors: number;
    avg_latency_ms: number | null;
    cost_usd: number;
  }[];
  apple_limit_hits: { date: string; users: number }[];
  errors: {
    id: string;
    at: string;
    user_id: string;
    username: string | null;
    provider: Provider;
    kind: string;
    error: string;
  }[];
  totals: {
    calls: number;
    users: number;
    errors: number;
    avg_latency_ms: number | null;
    cost_usd: number;
  };
};

type Spend = {
  month: string;
  spent_usd: number;
  calls: number;
  cap_usd: number;
  stop_at_usd: number;
  warn_at_usd: [number, number];
  stopped: boolean;
  stopped_at: string | null;
  by_day: { date: string; cost_usd: number }[];
  by_model: { model: string; calls: number; cost_usd: number }[];
  by_user: { user_id: string; username: string | null; calls: number; cost_usd: number }[];
};

type CoachUser = {
  user_id: string;
  username: string | null;
  display_name: string | null;
  plus: boolean;
  ai_mode: AiMode;
  user_opt_out: boolean;
  has_plan: boolean;
  calls_30d: number;
  cost_30d_usd: number;
  last_call_at: string | null;
};

type AiCall = {
  id: string;
  user_id: string;
  username?: string | null;
  provider: Provider;
  kind: string;
  trigger: string | null;
  model: string | null;
  started_at: string | null;
  created_at: string;
  latency_ms: number | null;
  tokens_in: number | null;
  tokens_out: number | null;
  tokens_cached: number | null;
  cost_usd: number | null;
  error: string | null;
  daily_limit_hit: boolean;
  input_preview?: string | null;
  output_preview?: string | null;
  input?: string | null;
  output?: string | null;
  tool_calls?: unknown;
  proposal_ids: string[] | null;
};

type Note = {
  id: string;
  user_id: string | null;
  username: string | null;
  plan_id: string | null;
  proposal_id: string | null;
  body: string;
  status: "open" | "resolved";
  source: string;
  created_at: string;
  resolved_at: string | null;
};

type PlanDay = {
  local_date: string;
  kind: string;
  title: string;
  subtitle?: string | null;
  distance_mi: number;
  status?: string;
  note_source?: string | null;
  grade?: { score: number } | null;
  completed?: { distance_mi: number } | null;
};

type Proposal = {
  id: string;
  source: string;
  kind: string;
  status: string;
  title: string;
  reason: string;
  changes: { local_date: string; before: PlanDay | null; after: PlanDay }[];
  checks?: { text?: string; deviation_reason?: string | null };
  created_at: string;
  decided_at: string | null;
  applied_at: string | null;
};

type Goal = {
  type: string;
  distance?: string;
  distance_mi?: number;
  target_s?: number | null;
  current_s?: number | null;
  weekly_minutes?: number;
};

type UserDetail = {
  user: {
    user_id: string;
    username: string | null;
    first_name: string | null;
    plus: boolean;
    ai_mode: AiMode;
    user_opt_out: boolean;
    anthropic_consent_at: string | null;
  };
  plan: {
    plan_id: string;
    status: string;
    goals: Goal[];
    target_date: string | null;
    runs_per_week: number;
    difficulty: number;
    walk_mode: string;
    start_date: string;
    week_index: number;
    phase: string;
    weekly_target_mi: number;
    coach_notes: string | null;
  } | null;
  days: PlanDay[];
  proposals: Proposal[];
  history: { id: string; at: string; event: string; source: string | null; summary: string }[];
  calls: AiCall[];
};

// ─── Formatting ─────────────────────────────────────────────────────

const usd = (n: number | null | undefined, digits = 2) =>
  n == null ? "—" : `$${Number(n).toFixed(digits)}`;
const secs = (ms: number | null | undefined) =>
  ms == null ? "—" : `${(ms / 1000).toFixed(1)} s`;
const DIFFICULTY = ["", "Easy does it", "Steady", "Push", "All in"];
const PROVIDER_LABEL: Record<string, string> = { apple: "Apple", anthropic: "Anthropic" };

function clock(s: number | null | undefined) {
  if (s == null) return "—";
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = Math.round(s % 60);
  return h
    ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`
    : `${m}:${String(sec).padStart(2, "0")}`;
}

function goalText(g: Goal) {
  if (g.type === "distance_time") {
    const d = g.distance === "custom" ? `${g.distance_mi} mi` : (g.distance ?? "").toUpperCase();
    return `${d} in ${clock(g.target_s)}${g.current_s ? ` (now ${clock(g.current_s)})` : ""}`;
  }
  if (g.type === "burn_calories") return `Move ${g.weekly_minutes ?? 150} min a week`;
  if (g.type === "just_improve") return "Just improve";
  return g.type;
}

function utcDays(n: number): string[] {
  const out: string[] = [];
  const now = new Date();
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - i));
    out.push(d.toISOString().slice(0, 10));
  }
  return out;
}

// ─── Small controls ─────────────────────────────────────────────────

function Toggle({
  label,
  on,
  busy,
  onChange,
}: {
  label: string;
  on: boolean;
  busy?: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <button
      role="switch"
      aria-checked={on}
      disabled={busy}
      onClick={() => onChange(!on)}
      className="flex items-center gap-2 rounded-full border border-white/[0.12] px-3 py-1.5 text-xs font-semibold text-white/70 transition hover:border-white/25 disabled:opacity-50"
    >
      <span>{label}</span>
      <span
        className="relative h-5 w-9 shrink-0 rounded-full transition"
        style={{ background: on ? MAD_SUCCESS : "rgba(255,255,255,0.15)" }}
      >
        <span
          className="absolute top-0.5 h-4 w-4 rounded-full bg-white transition-all"
          style={{ left: on ? 18 : 2 }}
        />
      </span>
    </button>
  );
}

const MODES: { value: AiMode; label: string }[] = [
  { value: "off", label: "Off" },
  { value: "apple", label: "Apple" },
  { value: "anthropic", label: "Anthropic" },
];

/**
 * Off / Apple / Anthropic for one person. Optimistic: the pill moves at once,
 * and snaps back (with the backend's error) if the PUT fails.
 */
export function AiModeControl({
  userId,
  value,
  onSaved,
}: {
  userId: string;
  value: AiMode;
  onSaved?: (m: AiMode) => void;
}) {
  const [mode, setMode] = useState<AiMode>(value);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => setMode(value), [value]);

  async function choose(m: AiMode) {
    if (m === mode) return;
    const prev = mode;
    setMode(m);
    setErr(null);
    try {
      const r = await putData<{ ai_mode: AiMode }>(
        `coach/users/${encodeURIComponent(userId)}/ai-mode`,
        { ai_mode: m },
      );
      setMode(r.ai_mode);
      onSaved?.(r.ai_mode);
    } catch (e) {
      setMode(prev);
      if ((e as Error)?.message !== "unauthorized") setErr((e as Error).message);
    }
  }

  return (
    <span className="inline-flex flex-col items-start gap-1" onClick={(e) => e.stopPropagation()}>
      <span className="inline-flex rounded-lg bg-white/[0.07] p-0.5 text-[11.5px]">
        {MODES.map((m) => (
          <button
            key={m.value}
            onClick={() => choose(m.value)}
            aria-pressed={mode === m.value}
            className={`rounded-md px-2.5 py-1 transition ${
              mode === m.value
                ? "bg-white/[0.16] font-semibold text-white"
                : "text-white/45 hover:text-white/80"
            }`}
          >
            {m.label}
          </button>
        ))}
      </span>
      {err && <span className="text-[11px] text-[#ff9aae]">Not saved: {err}</span>}
    </span>
  );
}

function ProviderDot({ provider }: { provider: string }) {
  const color = provider === "apple" ? SERIES[0] : provider === "anthropic" ? SERIES[1] : "rgba(255,255,255,0.3)";
  return (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap">
      <span className="h-[7px] w-[7px] rounded-full" style={{ background: color }} aria-hidden />
      {PROVIDER_LABEL[provider] ?? provider}
    </span>
  );
}

function Overlay({
  onClose,
  z = "z-50",
  wide,
  children,
}: {
  onClose: () => void;
  z?: string;
  wide?: boolean;
  children: ReactNode;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [onClose]);
  return (
    <div
      className={`fixed inset-0 ${z} flex items-start justify-center overflow-y-auto bg-black/70 p-3 backdrop-blur-sm sm:p-8`}
      onClick={onClose}
    >
      <div
        className={`w-full ${wide ? "max-w-4xl" : "max-w-3xl"} min-w-0 rounded-2xl border border-white/[0.08] shadow-2xl`}
        style={{ background: PANEL_BACKGROUND }}
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </div>
    </div>
  );
}

function PanelHeader({ title, sub, onClose }: { title: ReactNode; sub?: ReactNode; onClose: () => void }) {
  return (
    <div className="flex items-start gap-4 border-b border-white/[0.08] px-5 pt-5 pb-4">
      <div className="min-w-0 flex-1">
        <h2 className="text-lg font-semibold break-words text-white">{title}</h2>
        {sub && <div className="mt-0.5 text-sm break-words text-white/50">{sub}</div>}
      </div>
      <button
        onClick={onClose}
        className="shrink-0 rounded-full border border-white/[0.12] px-3 py-1 text-sm text-white/60 transition hover:text-white"
      >
        Close
      </button>
    </div>
  );
}

function Heading({ children }: { children: ReactNode }) {
  return (
    <h3 className="mb-2 text-[11px] font-semibold tracking-[0.4px] text-white/45 uppercase">
      {children}
    </h3>
  );
}

// ─── Call log table + viewer ────────────────────────────────────────

function CallsTable({
  calls,
  showUser,
  onOpen,
  onOpenUser,
}: {
  calls: AiCall[];
  showUser?: boolean;
  onOpen: (id: string) => void;
  onOpenUser?: (userId: string) => void;
}) {
  if (!calls.length) return <p className="text-sm text-white/40">No AI calls yet.</p>;
  return (
    <div className="-mx-5 overflow-x-auto">
      <table className="w-full min-w-[640px] text-sm">
        <thead>
          <tr className="border-b border-white/10 text-left text-xs text-white/40">
            <th className="px-5 py-2 font-medium">Time</th>
            {showUser && <th className="py-2 pr-3 font-medium">User</th>}
            <th className="py-2 pr-3 font-medium">Type</th>
            <th className="py-2 pr-3 font-medium">Provider</th>
            <th className="py-2 pr-3 font-medium">Model</th>
            <th className="py-2 pr-3 text-right font-medium">In</th>
            <th className="py-2 pr-3 text-right font-medium">Out</th>
            <th className="py-2 pr-3 text-right font-medium">Cost</th>
            <th className="py-2 pr-5 text-right font-medium">Latency</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-white/5">
          {calls.map((c) => (
            <tr
              key={c.id}
              onClick={() => onOpen(c.id)}
              className="cursor-pointer transition hover:bg-white/[0.03]"
            >
              <td className="px-5 py-2 whitespace-nowrap text-white/60">{fmtDateTime(c.created_at)}</td>
              {showUser && (
                <td className="py-2 pr-3 whitespace-nowrap">
                  <button
                    className="text-white/85 hover:text-white"
                    onClick={(e) => {
                      e.stopPropagation();
                      onOpenUser?.(c.user_id);
                    }}
                  >
                    {c.username ? `@${c.username}` : c.user_id.slice(0, 8)}
                  </button>
                </td>
              )}
              <td className="py-2 pr-3">
                <span className="text-white/85">
                  {c.kind.replace(/_/g, " ")}
                  {c.trigger && <span className="text-white/40"> · {c.trigger.replace(/_/g, " ")}</span>}
                </span>
                {(c.error || c.daily_limit_hit) && (
                  <div className="text-[11px]" style={{ color: MAD_WARNING }}>
                    {c.daily_limit_hit ? "Apple daily limit reached" : c.error}
                  </div>
                )}
              </td>
              <td className="py-2 pr-3 text-white/70"><ProviderDot provider={c.provider} /></td>
              <td className="py-2 pr-3 whitespace-nowrap text-white/60">{c.model ?? "—"}</td>
              <td className="py-2 pr-3 text-right tabular-nums text-white/70">{c.tokens_in != null ? fmt(c.tokens_in) : "—"}</td>
              <td className="py-2 pr-3 text-right tabular-nums text-white/70">{c.tokens_out != null ? fmt(c.tokens_out) : "—"}</td>
              <td className="py-2 pr-3 text-right whitespace-nowrap tabular-nums text-white/70">
                {c.provider === "apple" ? <span className="text-white/40">$0</span> : usd(c.cost_usd, 4)}
              </td>
              <td className="py-2 pr-5 text-right tabular-nums text-white/55">{secs(c.latency_ms)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function TextBlock({ label, text }: { label: string; text: string | null | undefined }) {
  const [copied, setCopied] = useState(false);
  return (
    <div>
      <div className="mb-1.5 flex items-center justify-between gap-2">
        <Heading>{label}</Heading>
        {text && (
          <button
            onClick={() => {
              void navigator.clipboard?.writeText(text).then(() => {
                setCopied(true);
                setTimeout(() => setCopied(false), 1200);
              });
            }}
            className="mb-2 rounded-full border border-white/[0.12] px-2.5 py-0.5 text-[11px] text-white/55 hover:text-white"
          >
            {copied ? "Copied" : "Copy"}
          </button>
        )}
      </div>
      {text ? (
        <pre className="max-h-[50vh] overflow-auto rounded-xl border border-white/[0.08] bg-black/40 p-3 font-mono text-[12px] leading-relaxed break-words whitespace-pre-wrap text-white/80">
          {prettyJson(text)}
        </pre>
      ) : (
        <p className="text-sm text-white/40">Not recorded.</p>
      )}
    </div>
  );
}

function prettyJson(s: string) {
  const t = s.trim();
  if (!(t.startsWith("{") || t.startsWith("["))) return s;
  try {
    return JSON.stringify(JSON.parse(t), null, 2);
  } catch {
    return s;
  }
}

function CallViewer({ id, onClose }: { id: string; onClose: () => void }) {
  const [call, setCall] = useState<AiCall | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    getData<{ call: AiCall }>(`coach/calls/${encodeURIComponent(id)}`)
      .then((r) => setCall(r.call))
      .catch((e) => e?.message !== "unauthorized" && setErr("Could not load this call."));
  }, [id]);
  return (
    <Overlay onClose={onClose} z="z-[60]" wide>
      <PanelHeader
        title={call ? `${call.kind.replace(/_/g, " ")} · ${PROVIDER_LABEL[call.provider] ?? call.provider}` : "AI call"}
        sub={call ? `${fmtDateTime(call.created_at)}${call.model ? ` · ${call.model}` : ""}` : null}
        onClose={onClose}
      />
      <div className="space-y-5 p-5">
        {err && <p className="text-sm text-[#ff9aae]">{err}</p>}
        {!call && !err && <Loading />}
        {call && (
          <>
            <div className={`grid grid-cols-2 sm:grid-cols-4 ${TILE}`}>
              <Mini label="Tokens in" value={call.tokens_in != null ? fmt(call.tokens_in) : "—"} />
              <Mini label="Tokens out" value={call.tokens_out != null ? fmt(call.tokens_out) : "—"} />
              <Mini label="Cost" value={call.provider === "apple" ? "$0" : usd(call.cost_usd, 4)} />
              <Mini label="Latency" value={secs(call.latency_ms)} />
            </div>
            {(call.error || call.daily_limit_hit) && (
              <p className="rounded-xl border px-3 py-2 text-sm" style={{ borderColor: `${MAD_WARNING}55`, color: MAD_WARNING }}>
                {call.daily_limit_hit ? "Apple daily limit reached; fell back to the formula plan. " : ""}
                {call.error ?? ""}
              </p>
            )}
            <div className="flex flex-wrap gap-2 text-xs text-white/45">
              {call.trigger && <Chip text={`trigger: ${call.trigger.replace(/_/g, " ")}`} />}
              {call.tokens_cached ? <Chip text={`${fmt(call.tokens_cached)} cached`} /> : null}
              {(call.proposal_ids ?? []).length > 0 && (
                <Chip text={`${call.proposal_ids!.length} proposal(s)`} tone="info" />
              )}
            </div>
            <TextBlock label="Input" text={call.input} />
            <TextBlock label="Output" text={call.output} />
            {call.tool_calls != null && (
              <TextBlock label="Tool calls" text={JSON.stringify(call.tool_calls)} />
            )}
          </>
        )}
      </div>
    </Overlay>
  );
}

function Mini({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.05] px-3 py-2.5">
      <div className="text-[10px] font-semibold tracking-[0.4px] text-white/55 uppercase">{label}</div>
      <div className="mad-num mt-0.5 text-lg font-extrabold text-white">{value}</div>
    </div>
  );
}

// ─── Per-user drilldown ─────────────────────────────────────────────

const STATUS_TONE: Record<string, "ok" | "bad" | "muted" | "info"> = {
  applied: "ok",
  pending: "info",
  scheduled: "info",
  declined: "bad",
  undone: "bad",
};

function dayLine(d: PlanDay | null) {
  if (!d) return "—";
  if (d.kind === "walk") return "Walk day";
  return `${d.title}${d.distance_mi ? ` · ${d.distance_mi.toFixed(1)} mi` : ""}`;
}

function CoachUserPanel({
  userId,
  onClose,
  onOpenCall,
  onModeSaved,
}: {
  userId: string;
  onClose: () => void;
  onOpenCall: (id: string) => void;
  onModeSaved?: (userId: string, m: AiMode) => void;
}) {
  const [d, setD] = useState<UserDetail | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    getData<UserDetail>(`coach/users/${encodeURIComponent(userId)}`)
      .then(setD)
      .catch((e) => e?.message !== "unauthorized" && setErr("Could not load this member."));
  }, [userId]);

  const today = new Date().toISOString().slice(0, 10);
  const recent = d?.days.filter((x) => x.local_date < today).slice(-10).reverse() ?? [];
  const upcoming = d?.days.filter((x) => x.local_date >= today).slice(0, 14) ?? [];

  return (
    <Overlay onClose={onClose} wide>
      <PanelHeader
        title={d ? (d.user.username ? `@${d.user.username}` : d.user.first_name ?? userId.slice(0, 8)) : "Loading…"}
        sub={
          d && (
            <span className="flex flex-wrap items-center gap-2">
              {d.user.plus ? <Chip text="Mile A Day+" tone="ok" /> : <Chip text="Not Plus" />}
              {d.user.user_opt_out && <Chip text="opted out of AI" tone="bad" />}
              {d.user.anthropic_consent_at && (
                <span className="text-xs text-white/40">Anthropic consent {fmtDate(d.user.anthropic_consent_at)}</span>
              )}
            </span>
          )
        }
        onClose={onClose}
      />
      <div className="space-y-6 p-5">
        {err && <p className="text-sm text-[#ff9aae]">{err}</p>}
        {!d && !err && <Loading />}
        {d && (
          <>
            <div className="flex flex-wrap items-center gap-3">
              <span className="text-sm text-white/50">AI mode</span>
              <AiModeControl
                userId={userId}
                value={d.user.ai_mode}
                onSaved={(m) => onModeSaved?.(userId, m)}
              />
            </div>

            <div>
              <Heading>Plan</Heading>
              {!d.plan ? (
                <p className="text-sm text-white/40">No active plan.</p>
              ) : (
                <div className="space-y-2 text-sm">
                  <div className="flex flex-wrap gap-1.5">
                    {d.plan.goals.map((g, i) => (
                      <Chip key={i} text={goalText(g)} tone="info" />
                    ))}
                  </div>
                  <p className="text-white/70">
                    {d.plan.runs_per_week} runs a week · {DIFFICULTY[d.plan.difficulty] ?? d.plan.difficulty} ·
                    walk days {d.plan.walk_mode.replace(/_/g, " ")} · week {d.plan.week_index + 1} ({d.plan.phase}) ·
                    {" "}{d.plan.weekly_target_mi} mi target
                  </p>
                  <p className="text-white/45">
                    Started {fmtDate(d.plan.start_date)}
                    {d.plan.target_date ? ` · target ${fmtDate(d.plan.target_date)}` : " · no target date"}
                  </p>
                  {d.plan.coach_notes && (
                    <p className="rounded-lg bg-white/[0.03] px-3 py-2 text-white/65">Notes for the coach: {d.plan.coach_notes}</p>
                  )}
                </div>
              )}
            </div>

            {d.plan && (
              <div className="grid gap-5 sm:grid-cols-2">
                <DayList title="Next 14 days" days={upcoming} />
                <DayList title="Recent" days={recent} />
              </div>
            )}

            <div>
              <Heading>Proposals ({d.proposals.length})</Heading>
              {d.proposals.length === 0 ? (
                <p className="text-sm text-white/40">None yet.</p>
              ) : (
                <ul className="space-y-2.5">
                  {d.proposals.slice(0, 40).map((p) => (
                    <li key={p.id} className="rounded-xl border border-white/[0.08] bg-white/[0.03] p-3 text-sm">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-semibold text-white/90">{p.title}</span>
                        <Chip text={p.status} tone={STATUS_TONE[p.status] ?? "muted"} />
                        <Chip text={p.source.replace(/_/g, " ")} />
                        <span className="ml-auto text-xs text-white/40">
                          {fmtDateTime(p.created_at)}
                          {p.decided_at ? ` · decided ${fmtDateTime(p.decided_at)}` : ""}
                        </span>
                      </div>
                      <p className="mt-1 text-white/60">{p.reason}</p>
                      <ul className="mt-2 space-y-1 text-[13px]">
                        {p.changes.map((c) => (
                          <li key={c.local_date} className="grid grid-cols-[84px_1fr] gap-2">
                            <span className="text-white/45">{c.local_date}</span>
                            <span className="min-w-0 break-words">
                              <span className="text-white/40 line-through">{dayLine(c.before)}</span>
                              <span className="text-white/40"> → </span>
                              <span className="text-white/85">{dayLine(c.after)}</span>
                            </span>
                          </li>
                        ))}
                      </ul>
                      {p.checks?.text && <p className="mt-1.5 text-xs text-white/40">{p.checks.text}</p>}
                      {p.checks?.deviation_reason && (
                        <p className="mt-1 text-xs text-white/40">Deviation: {p.checks.deviation_reason}</p>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </div>

            {d.history.length > 0 && (
              <div>
                <Heading>History</Heading>
                <ul className="divide-y divide-white/5 text-sm">
                  {d.history.slice(0, 30).map((h) => (
                    <li key={h.id} className="flex flex-wrap items-baseline gap-x-3 py-1.5">
                      <span className="w-36 shrink-0 text-xs text-white/40">{fmtDateTime(h.at)}</span>
                      <span className="text-white/55">{h.event.replace(/_/g, " ")}</span>
                      {h.source && <span className="text-xs text-white/35">{h.source}</span>}
                      <span className="min-w-0 flex-1 basis-48 text-white/80">{h.summary}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            <div>
              <Heading>AI calls ({d.calls.length})</Heading>
              <div className="px-5">
                <CallsTable calls={d.calls} onOpen={onOpenCall} />
              </div>
            </div>
          </>
        )}
      </div>
    </Overlay>
  );
}

function DayList({ title, days }: { title: string; days: PlanDay[] }) {
  return (
    <div>
      <Heading>{title}</Heading>
      {days.length === 0 ? (
        <p className="text-sm text-white/40">Nothing here.</p>
      ) : (
        <ul className="divide-y divide-white/5 text-sm">
          {days.map((x) => (
            <li key={x.local_date} className="flex items-baseline justify-between gap-3 py-1.5">
              <span className="min-w-0">
                <span className="mr-2 text-xs text-white/40">{x.local_date.slice(5)}</span>
                <span className="text-white/80">{dayLine(x)}</span>
              </span>
              <span className="flex shrink-0 items-center gap-1.5">
                {x.grade && <span className="text-xs tabular-nums text-white/55">{x.grade.score}</span>}
                {x.status && x.status !== "planned" && (
                  <Chip
                    text={x.status.replace(/_/g, " ")}
                    tone={x.status === "done" || x.status === "walk_done" ? "ok" : x.status === "missed" ? "bad" : "muted"}
                  />
                )}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

// ─── Panels ─────────────────────────────────────────────────────────

function UsagePanel({ usage }: { usage: Usage }) {
  const days = utcDays(usage.days);
  const byDate = new Map(days.map((d) => [d, { date: d, apple: 0, anthropic: 0 }]));
  const lat: Record<Provider, { ms: number; n: number }> = { apple: { ms: 0, n: 0 }, anthropic: { ms: 0, n: 0 } };
  const calls: Record<Provider, number> = { apple: 0, anthropic: 0 };
  for (const r of usage.by_day) {
    const row = byDate.get(r.date);
    if (row && (r.provider === "apple" || r.provider === "anthropic")) row[r.provider] += r.calls;
    if (r.provider in calls) calls[r.provider] += r.calls;
    if (r.avg_latency_ms != null && r.provider in lat) {
      lat[r.provider].ms += r.avg_latency_ms * r.calls;
      lat[r.provider].n += r.calls;
    }
  }
  const avg = (p: Provider) => (lat[p].n ? secs(lat[p].ms / lat[p].n) : "—");
  const todayKey = days[days.length - 1];
  const hitsToday = usage.apple_limit_hits.find((h) => h.date === todayKey)?.users ?? 0;
  const hitDays = usage.apple_limit_hits.filter((h) => h.users > 0).length;
  const errRate = usage.totals.calls ? (usage.totals.errors / usage.totals.calls) * 100 : 0;

  return (
    <div className={`grid gap-5 lg:grid-cols-[1.7fr_1fr]`}>
      <Card>
        <StackedDayBars
          data={[...byDate.values()]}
          series={[
            { key: "apple", label: "Apple", color: SERIES[0] },
            { key: "anthropic", label: "Anthropic", color: SERIES[1] },
          ]}
          label="AI calls per day (UTC)"
          hint={`${fmt(calls.apple)} Apple · ${fmt(calls.anthropic)} Anthropic · ${fmt(usage.totals.users)} members called the coach`}
          windowDays={usage.days}
          emptyText={`No AI Coach calls in the last ${usage.days} days.`}
        />
      </Card>
      <div className={`grid grid-cols-2 content-start ${TILE}`}>
        <StatCard
          label="Hit Apple limit"
          value={`${hitsToday} today`}
          sub={`On ${hitDays} of ${usage.days} days · fell back to the formula plan until the next day`}
        />
        <StatCard
          label="Errors"
          value={`${errRate.toFixed(1)}%`}
          sub={`${fmt(usage.totals.errors)} of ${fmt(usage.totals.calls)} calls`}
        />
        <StatCard label="Avg latency" value={avg("apple")} sub="Apple" />
        <StatCard label="Avg latency" value={avg("anthropic")} sub="Anthropic" />
      </div>
      {usage.errors.length > 0 && (
        <Card title="Recent errors" className="lg:col-span-2">
          <ul className="divide-y divide-white/5 text-sm">
            {usage.errors.slice(0, 8).map((e) => (
              <li key={e.id} className="flex flex-wrap items-baseline gap-x-3 py-1.5">
                <span className="w-36 shrink-0 text-xs text-white/40">{fmtDateTime(e.at)}</span>
                <span className="text-white/70">{e.username ? `@${e.username}` : e.user_id.slice(0, 8)}</span>
                <span className="text-white/45"><ProviderDot provider={e.provider} /> · {e.kind.replace(/_/g, " ")}</span>
                <span className="min-w-0 flex-1 basis-48 break-words" style={{ color: MAD_WARNING }}>{e.error}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  );
}

function SpendCard({ spend, onOpenUser }: { spend: Spend; onOpenUser: (id: string) => void }) {
  const cap = spend.cap_usd || 50;
  const at = (v: number) => `${Math.min(100, Math.max(0, (v / cap) * 100))}%`;
  const markers: [number, string, string][] = [
    [spend.warn_at_usd[0], `Warn $${spend.warn_at_usd[0]}`, MAD_WARNING],
    [spend.warn_at_usd[1], `Warn $${spend.warn_at_usd[1]}`, MAD_WARNING],
    [spend.stop_at_usd, `Stop $${spend.stop_at_usd}`, MAD_ERROR],
  ];
  const [y, m] = spend.month.split("-").map(Number);
  const reset = new Date(Date.UTC(y, m, 1)).toLocaleDateString(undefined, { month: "short", day: "numeric", timeZone: "UTC" });
  const barColor = spend.spent_usd >= spend.stop_at_usd ? MAD_ERROR : spend.spent_usd >= spend.warn_at_usd[0] ? MAD_WARNING : MAD_SUCCESS;
  return (
    <Card
      title="Anthropic spend"
      hint={`Optional provider · ${spend.month} · resets ${reset}`}
      actions={spend.stopped ? <Chip text="stopped" tone="bad" /> : undefined}
    >
      <div className="flex flex-wrap items-baseline gap-2">
        <span className="mad-num text-[28px] leading-none font-extrabold">{usd(spend.spent_usd)}</span>
        <span className="text-sm text-white/45">of {usd(cap)} cap · {fmt(spend.calls)} calls</span>
      </div>
      <div className="relative mt-4 h-2 rounded-full bg-white/10">
        <div className="h-full rounded-full" style={{ width: at(spend.spent_usd), background: barColor }} />
        {markers.map(([v, , c]) => (
          <div key={v} className="absolute -top-1 h-4 w-0.5" style={{ left: at(v), background: c }} />
        ))}
      </div>
      {/* Labels sit under their marker; the last is right-aligned so "Stop"
          never runs off a phone-width card. */}
      <div className="relative mt-1 h-4 text-[10.5px] text-white/50">
        {markers.map(([v, l], i) => (
          <span
            key={v}
            className={`absolute whitespace-nowrap ${i === markers.length - 1 ? "-translate-x-full" : "-translate-x-1/2"}`}
            style={{ left: at(v) }}
          >
            {l}
          </span>
        ))}
      </div>
      <div className="mt-4 space-y-1 text-[12.5px]">
        {spend.by_model.length === 0 ? (
          <p className="text-white/40">No Anthropic calls this month.</p>
        ) : (
          spend.by_model.map((x) => (
            <div key={x.model} className="flex justify-between gap-3">
              <span className="truncate text-white/80">{x.model}</span>
              <span className="shrink-0 tabular-nums text-white/50">{usd(x.cost_usd)} · {fmt(x.calls)} calls</span>
            </div>
          ))
        )}
      </div>
      {spend.by_user.length > 0 && (
        <div className="mt-3 space-y-1 border-t border-white/[0.06] pt-3 text-[12.5px]">
          {spend.by_user.slice(0, 5).map((u) => (
            <button
              key={u.user_id}
              onClick={() => onOpenUser(u.user_id)}
              className="flex w-full justify-between gap-3 rounded px-1 text-left hover:bg-white/[0.05]"
            >
              <span className="truncate text-white/80">{u.username ? `@${u.username}` : u.user_id.slice(0, 8)}</span>
              <span className="shrink-0 tabular-nums text-white/50">{usd(u.cost_usd)} · {fmt(u.calls)} calls</span>
            </button>
          ))}
        </div>
      )}
      <p className="mt-3 text-[11.5px] text-white/40">
        At {usd(spend.stop_at_usd, 0)} Anthropic users fall back to Apple or the formula plan until the month resets.
      </p>
    </Card>
  );
}

type NoteFilter = "open" | "resolved" | "all";

function NotesCard({ onOpenUser }: { onOpenUser: (id: string) => void }) {
  const [filter, setFilter] = useState<NoteFilter>("open");
  const [notes, setNotes] = useState<Note[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => {
    setNotes(null);
    getData<{ notes: Note[] }>(`coach/review-notes?status=${filter}`)
      .then((r) => setNotes(r.notes))
      .catch((e) => e?.message !== "unauthorized" && setErr("Could not load review notes."));
  }, [filter]);

  async function setStatus(n: Note, status: "open" | "resolved") {
    setBusy(n.id);
    try {
      const updated = await patchData<Note>(`coach/review-notes/${encodeURIComponent(n.id)}`, { status });
      setNotes((cur) =>
        (cur ?? [])
          .map((x) => (x.id === n.id ? { ...x, ...updated, username: x.username } : x))
          .filter((x) => filter === "all" || x.status === filter),
      );
    } catch (e) {
      if ((e as Error)?.message !== "unauthorized") setErr(`Not saved: ${(e as Error).message}`);
    } finally {
      setBusy(null);
    }
  }

  return (
    <Card
      title="Review notes"
      hint="Findings saved by the overseer connector (review_note) or an admin"
      actions={
        <SegmentedControl<NoteFilter>
          value={filter}
          onChange={setFilter}
          options={[
            { value: "open", label: "Open" },
            { value: "resolved", label: "Resolved" },
            { value: "all", label: "All" },
          ]}
        />
      }
    >
      {err && <p className="mb-2 text-sm text-[#ff9aae]">{err}</p>}
      {!notes ? (
        <Loading />
      ) : notes.length === 0 ? (
        <p className="text-sm text-white/40">{filter === "open" ? "No open notes." : "No notes."}</p>
      ) : (
        <ul className="max-h-[420px] space-y-2.5 overflow-y-auto">
          {notes.map((n) => (
            <li
              key={n.id}
              className="rounded-xl border p-3 text-sm"
              style={{
                borderColor: n.status === "open" ? `${MAD_WARNING}55` : "rgba(255,255,255,0.08)",
                background: n.status === "open" ? `${MAD_WARNING}0f` : "rgba(255,255,255,0.03)",
              }}
            >
              <div className="flex flex-wrap items-center gap-2 text-[12px]">
                <span className="font-semibold text-white/90">{n.username ? `@${n.username}` : "General"}</span>
                <Chip text={n.source} tone={n.source === "overseer" ? "info" : "muted"} />
                {n.status === "resolved" && <Chip text="resolved" tone="ok" />}
                <span className="ml-auto text-white/40">{fmtDateTime(n.created_at)}</span>
              </div>
              <p className="mt-2 leading-snug break-words whitespace-pre-wrap text-white/80">{n.body}</p>
              <div className="mt-2 flex flex-wrap items-center justify-end gap-2 text-[12px]">
                {n.user_id && (
                  <button
                    onClick={() => onOpenUser(n.user_id!)}
                    className="rounded-full px-3 py-1 text-white/60 hover:text-white"
                  >
                    Open plan
                  </button>
                )}
                <button
                  disabled={busy === n.id}
                  onClick={() => setStatus(n, n.status === "open" ? "resolved" : "open")}
                  className="rounded-full bg-white/10 px-3 py-1 text-white/85 transition hover:bg-white/15 disabled:opacity-50"
                >
                  {n.status === "open" ? "Mark resolved" : "Reopen"}
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

const USERS_PAGE = 25;

function MembersCard({
  onOpenUser,
  modeOverrides,
}: {
  onOpenUser: (id: string) => void;
  modeOverrides: Record<string, AiMode>;
}) {
  const [search, setSearch] = useState("");
  const [q, setQ] = useState("");
  const [offset, setOffset] = useState(0);
  const [data, setData] = useState<{ users: CoachUser[]; total: number } | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const t = setTimeout(() => {
      setQ(search.trim());
      setOffset(0);
    }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const p = new URLSearchParams({ limit: String(USERS_PAGE), offset: String(offset) });
      if (q) p.set("q", q);
      setData(await getData(`coach/users?${p.toString()}`));
    } catch {
      /* unauthorized handled in getData */
    } finally {
      setLoading(false);
    }
  }, [q, offset]);
  useEffect(() => {
    load();
  }, [load]);

  const total = data?.total ?? 0;
  const to = Math.min(offset + USERS_PAGE, total);

  return (
    <Card
      title="Mile A Day+ members · AI mode"
      hint="Apple by default. Also in each person's user modal."
      actions={
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Find member…"
          className="w-44 rounded-lg border border-white/10 bg-black/40 px-3 py-1.5 text-sm text-white placeholder:text-white/30 focus:border-[#d94059]/60 focus:outline-none"
        />
      }
    >
      {!data ? (
        <Loading />
      ) : data.users.length === 0 ? (
        <p className="text-sm text-white/40">{q ? "No members match." : "No Mile A Day+ members yet."}</p>
      ) : (
        <div className="-mx-5 overflow-x-auto">
          <table className="w-full min-w-[620px] text-sm">
            <thead>
              <tr className="border-b border-white/10 text-left text-xs text-white/40">
                <th className="px-5 py-2 font-medium">Member</th>
                <th className="py-2 pr-3 font-medium">AI mode</th>
                <th className="py-2 pr-3 font-medium">Plan</th>
                <th className="py-2 pr-3 text-right font-medium">Calls (30d)</th>
                <th className="py-2 pr-3 text-right font-medium">Cost (30d)</th>
                <th className="py-2 pr-5 text-right font-medium">Last call</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {data.users.map((u) => (
                <tr
                  key={u.user_id}
                  onClick={() => onOpenUser(u.user_id)}
                  className="cursor-pointer transition hover:bg-white/[0.03]"
                >
                  <td className="px-5 py-2">
                    <span className="text-white/90">{u.username ? `@${u.username}` : u.user_id.slice(0, 8)}</span>
                    {u.display_name && <span className="ml-2 text-white/40">{u.display_name}</span>}
                    {u.user_opt_out && <span className="ml-2"><Chip text="opted out" tone="bad" /></span>}
                  </td>
                  <td className="py-2 pr-3">
                    <AiModeControl userId={u.user_id} value={modeOverrides[u.user_id] ?? u.ai_mode} />
                  </td>
                  <td className="py-2 pr-3 text-white/60">{u.has_plan ? "Active" : "—"}</td>
                  <td className="py-2 pr-3 text-right tabular-nums">{u.calls_30d ? fmt(u.calls_30d) : "—"}</td>
                  <td className="py-2 pr-3 text-right tabular-nums text-white/60">
                    {u.cost_30d_usd ? usd(u.cost_30d_usd) : "—"}
                  </td>
                  <td className="py-2 pr-5 text-right whitespace-nowrap text-white/50">
                    {u.last_call_at ? relativeDay(u.last_call_at) : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {total > 0 && (
        <div className="mt-3 flex items-center justify-between gap-3 text-xs text-white/40">
          <button
            onClick={() => setOffset(Math.max(0, offset - USERS_PAGE))}
            disabled={offset === 0 || loading}
            className="rounded-md border border-white/10 px-3 py-1.5 text-white/60 hover:text-white disabled:opacity-30"
          >
            Prev
          </button>
          <span>{loading ? "Loading…" : `${offset + 1}–${to} of ${fmt(total)}`}</span>
          <button
            onClick={() => setOffset(offset + USERS_PAGE)}
            disabled={to >= total || loading}
            className="rounded-md border border-white/10 px-3 py-1.5 text-white/60 hover:text-white disabled:opacity-30"
          >
            Next
          </button>
        </div>
      )}
    </Card>
  );
}

type ProviderFilter = "all" | Provider;

function RecentCallsCard({ onOpenCall, onOpenUser }: { onOpenCall: (id: string) => void; onOpenUser: (id: string) => void }) {
  const [provider, setProvider] = useState<ProviderFilter>("all");
  const [calls, setCalls] = useState<AiCall[] | null>(null);
  const [more, setMore] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const PAGE = 50;

  const fetchPage = useCallback(
    async (before: string | null) => {
      const p = new URLSearchParams({ limit: String(PAGE) });
      if (provider !== "all") p.set("provider", provider);
      if (before) p.set("before", before);
      const r = await getData<{ calls: AiCall[] }>(`coach/calls?${p.toString()}`);
      setMore(r.calls.length === PAGE);
      return r.calls;
    },
    [provider],
  );

  useEffect(() => {
    setCalls(null);
    fetchPage(null)
      .then(setCalls)
      .catch((e) => e?.message !== "unauthorized" && setErr("Could not load calls."));
  }, [fetchPage]);

  return (
    <Card
      title="Recent AI calls · all members"
      hint="Kept 90 days, admins only. Apple calls are uploaded by the app; Anthropic calls are recorded on the server."
      actions={
        <SegmentedControl<ProviderFilter>
          value={provider}
          onChange={setProvider}
          options={[
            { value: "all", label: "All" },
            { value: "apple", label: "Apple" },
            { value: "anthropic", label: "Anthropic" },
          ]}
        />
      }
    >
      {err && <p className="text-sm text-[#ff9aae]">{err}</p>}
      {!calls ? (
        !err && <Loading />
      ) : (
        <>
          <CallsTable calls={calls} showUser onOpen={onOpenCall} onOpenUser={onOpenUser} />
          {more && calls.length > 0 && (
            <button
              onClick={async () => {
                const last = calls[calls.length - 1]?.created_at ?? null;
                const next = await fetchPage(last).catch(() => []);
                setCalls([...calls, ...next]);
              }}
              className="mt-3 rounded-md border border-white/10 px-3 py-1.5 text-xs text-white/60 hover:text-white"
            >
              Load more
            </button>
          )}
        </>
      )}
    </Card>
  );
}

// ─── Tab ────────────────────────────────────────────────────────────

export function CoachTab() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [savingSettings, setSavingSettings] = useState(false);
  const [settingsErr, setSettingsErr] = useState<string | null>(null);
  const [usage, setUsage] = useState<Usage | null>(null);
  const [spend, setSpend] = useState<Spend | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [openUser, setOpenUser] = useState<string | null>(null);
  const [openCall, setOpenCall] = useState<string | null>(null);
  const [modeOverrides, setModeOverrides] = useState<Record<string, AiMode>>({});

  useEffect(() => {
    const fail = (e: Error) => e?.message !== "unauthorized" && setErr("Some Coach data failed to load.");
    getData<Settings>("coach/settings").then(setSettings).catch(fail);
    getData<Usage>("coach/usage?days=30").then(setUsage).catch(fail);
    getData<Spend>("coach/spend").then(setSpend).catch(fail);
  }, []);

  async function saveSettings(patch: Partial<Settings>) {
    if (!settings) return;
    const prev = settings;
    setSettings({ ...settings, ...patch });
    setSavingSettings(true);
    setSettingsErr(null);
    try {
      setSettings(await putData<Settings>("coach/settings", patch));
    } catch (e) {
      setSettings(prev);
      if ((e as Error)?.message !== "unauthorized") setSettingsErr(`Not saved: ${(e as Error).message}`);
    } finally {
      setSavingSettings(false);
    }
  }

  const onModeSaved = useMemo(
    () => (userId: string, m: AiMode) => setModeOverrides((cur) => ({ ...cur, [userId]: m })),
    [],
  );

  return (
    <div className={STACK_SECTIONS}>
      <Section
        title="AI Coach"
        hint="Apple's cloud model by default, at no cost. Anthropic is optional, per member, inside the monthly cap. Off means the formula plan."
        actions={
          settings ? (
            <div className="flex flex-wrap items-center gap-2">
              <Toggle
                label="AI Coach for everyone"
                on={settings.ai_enabled}
                busy={savingSettings}
                onChange={(v) => saveSettings({ ai_enabled: v })}
              />
              <Toggle
                label="Anthropic provider"
                on={settings.anthropic_enabled}
                busy={savingSettings}
                onChange={(v) => saveSettings({ anthropic_enabled: v })}
              />
            </div>
          ) : undefined
        }
      >
        {settingsErr && <p className="text-sm text-[#ff9aae]">{settingsErr}</p>}
        {settings && !settings.ai_enabled && (
          <p className="rounded-xl border px-3 py-2 text-sm" style={{ borderColor: `${MAD_RED}55`, color: "#ffb3c6" }}>
            AI Coach is off for everyone. Every member is on the formula plan.
          </p>
        )}
        {err && <p className="text-sm text-[#ff9aae]">{err}</p>}
        {usage ? <UsagePanel usage={usage} /> : !err && <Loading />}
      </Section>

      <Section title="Spend and review">
        <div className="grid gap-5 lg:grid-cols-2">
          {spend ? <SpendCard spend={spend} onOpenUser={setOpenUser} /> : <Card><Loading /></Card>}
          <NotesCard onOpenUser={setOpenUser} />
        </div>
      </Section>

      <Section title="Members">
        <MembersCard onOpenUser={setOpenUser} modeOverrides={modeOverrides} />
      </Section>

      <Section title="Call log">
        <RecentCallsCard onOpenCall={setOpenCall} onOpenUser={setOpenUser} />
      </Section>

      {openUser && (
        <CoachUserPanel
          userId={openUser}
          onClose={() => setOpenUser(null)}
          onOpenCall={setOpenCall}
          onModeSaved={onModeSaved}
        />
      )}
      {openCall && <CallViewer id={openCall} onClose={() => setOpenCall(null)} />}
    </div>
  );
}
