"use client";

import type { ReactNode } from "react";

// ─── Data fetching (via the same-origin admin proxy) ────────────────

export async function getData<T>(path: string): Promise<T> {
  const res = await fetch(`/admin/api/data/${path}`, { cache: "no-store" });
  if (res.status === 401 || res.status === 403) {
    // Stale/invalid token — drop the cookie and return to login.
    await fetch("/admin/api/logout", { method: "POST" });
    window.location.reload();
    throw new Error("unauthorized");
  }
  if (!res.ok) throw new Error(`Request failed: ${res.status}`);
  return res.json();
}

/** POST an admin action; surfaces the backend's error message on failure. */
export async function postData<T>(path: string): Promise<T> {
  const res = await fetch(`/admin/api/data/${path}`, {
    method: "POST",
    cache: "no-store",
  });
  if (res.status === 401 || res.status === 403) {
    await fetch("/admin/api/logout", { method: "POST" });
    window.location.reload();
    throw new Error("unauthorized");
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body?.error || `Request failed: ${res.status}`);
  return body as T;
}

/** Signed media URLs come back as backend-relative paths — absolutize them. */
export function mediaSrc(url: string): string {
  if (url.startsWith("/")) {
    return `${process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech"}${url}`;
  }
  return url;
}

// ─── Formatting ─────────────────────────────────────────────────────

export const fmt = (n: number) =>
  n >= 1000
    ? n.toLocaleString(undefined, { maximumFractionDigits: 0 })
    : String(n);

export function fmtBytes(bytes: number): string {
  if (!bytes || bytes < 1) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB", "PB"];
  const i = Math.min(
    Math.floor(Math.log(bytes) / Math.log(1024)),
    units.length - 1,
  );
  const v = bytes / Math.pow(1024, i);
  return `${v.toFixed(i === 0 || v >= 100 ? 0 : 1)} ${units[i]}`;
}

export function fmtDate(iso?: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString();
}

export function fmtDateTime(iso?: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleString();
}

/** "today" / "yesterday" / "5d ago" for a YYYY-MM-DD or ISO date. */
export function relativeDay(dateStr?: string | null): string {
  if (!dateStr) return "never";
  const d = new Date(dateStr.length <= 10 ? `${dateStr}T00:00:00` : dateStr);
  if (Number.isNaN(d.getTime())) return "—";
  const today = new Date();
  const days = Math.floor(
    (new Date(today.toDateString()).getTime() -
      new Date(d.toDateString()).getTime()) /
      86_400_000,
  );
  if (days <= 0) return "today";
  if (days === 1) return "yesterday";
  if (days < 7) return `${days}d ago`;
  if (days < 30) return `${Math.floor(days / 7)}w ago`;
  if (days < 365) return `${Math.floor(days / 30)}mo ago`;
  return `${Math.floor(days / 365)}y ago`;
}

/**
 * The categorical set for charts that draw SEVERAL series at once, validated
 * against this dashboard's dark surface: every adjacent pair clears the
 * colour-vision separation floor, the normal-vision floor and 3:1 contrast,
 * and all three sit inside one lightness band so no series shouts louder than
 * the others. Burgundy leads to stay on brand.
 *
 * Assign these IN ORDER and never cycle them. A fourth concurrent series does
 * not get a made-up fourth hue — it becomes its own chart, because the next
 * step that still separates cleanly for a protanope does not exist here.
 */
export const SERIES = ["#c72554", "#0284c7", "#d97706"] as const;

// The single hue every heat grid ramps through, as "r, g, b" for rgba().
export const HEAT_HUE = "199, 37, 84";

// A wider palette for one-series-per-card breakdowns, where nothing has to be
// told apart from a neighbour at a glance. Not for stacked or grouped charts.
export const PALETTE = [
  "#c72554",
  "#38bdf8",
  "#fbbf24",
  "#34d399",
  "#a78bfa",
  "#f472b6",
  "#fb923c",
  "#60a5fa",
  "#9ca3af",
];

// ─── UI primitives ──────────────────────────────────────────────────

export function StatCard({
  label,
  value,
  sub,
  accent,
}: {
  label: string;
  value: string;
  sub?: ReactNode;
  accent?: boolean;
}) {
  return (
    <div
      className={`rounded-xl border p-5 ${
        accent
          ? "border-[#c72554]/40 bg-[#c72554]/10"
          : "border-white/10 bg-white/[0.03]"
      }`}
    >
      <div className="text-xs font-medium uppercase tracking-wide text-white/40">
        {label}
      </div>
      <div className="mt-1.5 text-3xl font-semibold text-white">{value}</div>
      {sub != null && <div className="mt-1 text-sm text-white/50">{sub}</div>}
    </div>
  );
}

export function Card({
  title,
  hint,
  actions,
  children,
  className = "",
}: {
  title?: ReactNode;
  hint?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`rounded-xl border border-white/10 bg-white/[0.03] p-5 ${className}`}
    >
      {(title || actions) && (
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            {title && (
              <h2 className="text-sm font-medium text-white/70">{title}</h2>
            )}
            {hint && <p className="mt-1 text-xs text-white/40">{hint}</p>}
          </div>
          {actions && <div className="shrink-0">{actions}</div>}
        </div>
      )}
      {children}
    </div>
  );
}

export function Chip({
  text,
  tone = "muted",
}: {
  text: string;
  tone?: "ok" | "bad" | "muted" | "info";
}) {
  const cls =
    tone === "ok"
      ? "bg-emerald-500/15 text-emerald-300"
      : tone === "bad"
        ? "bg-[#c72554]/20 text-[#ffb3c6]"
        : tone === "info"
          ? "bg-sky-500/15 text-sky-300"
          : "bg-white/10 text-white/60";
  return (
    <span
      className={`rounded px-1.5 py-0.5 text-[11px] font-medium whitespace-nowrap ${cls}`}
    >
      {text}
    </span>
  );
}

/** Horizontal proportional-bar list for categorical breakdowns. */
export function BarList({
  items,
  color = "#c72554",
  emptyLabel = "No data yet.",
  formatValue = (v: number) => fmt(v),
}: {
  items: { label: string; value: number; sub?: string }[];
  color?: string;
  emptyLabel?: string;
  formatValue?: (v: number) => string;
}) {
  if (!items.length)
    return <p className="text-sm text-white/40">{emptyLabel}</p>;
  const max = Math.max(...items.map((i) => i.value), 1);
  return (
    <ul className="space-y-2.5">
      {items.map((it) => (
        <li key={it.label}>
          <div className="mb-1 flex items-baseline justify-between gap-3 text-sm">
            <span className="truncate text-white/80">{it.label}</span>
            <span className="shrink-0 text-white/50">
              {it.sub ? `${it.sub} · ` : ""}
              <span className="text-white/90">{formatValue(it.value)}</span>
            </span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-white/[0.06]">
            <div
              className="h-full rounded-full"
              style={{
                width: `${(it.value / max) * 100}%`,
                background: color,
              }}
            />
          </div>
        </li>
      ))}
    </ul>
  );
}

/** "42%" from a part and a whole, with a zero whole reading as 0 rather than NaN. */
export const pct = (part: number, whole: number) =>
  whole > 0 ? Math.round((part / whole) * 100) : 0;

/**
 * A labelled proportion bar: the share of the user base that has ever touched
 * something, with the recent share drawn INSIDE it. Two nested bars rather
 * than two colours — "of the people who ever did this, these still do" is a
 * containment, and a grouped pair would invite reading them as rivals.
 */
export function AdoptionBar({
  label,
  everCount,
  recentCount,
  total,
  events,
}: {
  label: string;
  everCount: number;
  recentCount: number;
  total: number;
  events?: number;
}) {
  return (
    <li>
      {/* Label on its own line: these names are sentences ("Raced a friend's
          ghost"), and sharing a row with three numbers truncated every one of
          them to an ellipsis in a three-column layout. */}
      <div className="mb-1 flex items-baseline justify-between gap-3 text-sm">
        <span className="min-w-0 text-white/80">{label}</span>
        <span className="shrink-0 tabular-nums text-white/90">
          {fmt(everCount)}
        </span>
      </div>
      <div
        className="h-2.5 overflow-hidden rounded-full bg-white/[0.06]"
        role="img"
        aria-label={`${label}: ${everCount} of ${total} users ever, ${recentCount} in the last 30 days`}
      >
        <div
          className="relative h-full rounded-full"
          style={{
            width: `${pct(everCount, total)}%`,
            background: "rgba(199, 37, 84, 0.35)",
          }}
        >
          <div
            className="h-full rounded-full"
            style={{
              width: `${everCount > 0 ? pct(recentCount, everCount) : 0}%`,
              background: "#c72554",
            }}
          />
        </div>
      </div>
      <div className="mt-1 text-[11px] tabular-nums text-white/40">
        {pct(everCount, total)}% of users ·{" "}
        <span className="text-white/60">{fmt(recentCount)}</span> in the last
        30 days
        {events != null && <span> · {fmt(events)} times</span>}
      </div>
    </li>
  );
}

export function Loading({ label = "Loading…" }: { label?: string }) {
  return <p className="text-sm text-white/40">{label}</p>;
}

/** A subtle pill-style toggle group, used for filters/sorts across tabs. */
export function SegmentedControl<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: { value: T; label: string }[];
  onChange: (v: T) => void;
}) {
  return (
    <span className="flex flex-wrap gap-1">
      {options.map((o) => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          className={`rounded-full px-2.5 py-0.5 text-xs transition ${
            value === o.value
              ? "bg-[#c72554] text-white"
              : "border border-white/10 text-white/60 hover:text-white"
          }`}
        >
          {o.label}
        </button>
      ))}
    </span>
  );
}
