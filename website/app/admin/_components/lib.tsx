"use client";

import type { ReactNode } from "react";
import { CARD, CARD_INTERACTIVE, MAD_RED } from "./theme";

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

// The palette and card tokens now come from the app's own design system —
// see theme.ts, which is a direct port of MADTheme.swift. Re-exported here so
// every panel keeps importing them from one place.
export {
  SERIES,
  HEAT_HUE,
  PALETTE,
  MAD_RED,
  WALK_BLUE,
  MAD_SUCCESS,
  MAD_WARNING,
  CARD,
  CARD_INTERACTIVE,
  workoutColor,
} from "./theme";

// ─── UI primitives ──────────────────────────────────────────────────

export function StatCard({
  label,
  value,
  sub,
  accent,
  onClick,
}: {
  label: string;
  value: string;
  sub?: ReactNode;
  accent?: boolean;
  /** Present = this number opens the rows behind it. */
  onClick?: () => void;
}) {
  // Value and label mirror the app's stat cell (ProfileStatsRow): a heavy
  // rounded number over an 11px semibold tracked caption at 55% white.
  const body = (
    <>
      <div className="text-[11px] font-semibold tracking-[0.4px] text-white/55 uppercase">
        {label}
      </div>
      <div className="mad-num mt-1.5 text-[32px] leading-none font-extrabold text-white">
        {value}
      </div>
      {sub != null && (
        <div className="mt-1.5 text-[13px] text-white/45">{sub}</div>
      )}
    </>
  );

  const shell = accent
    ? "rounded-2xl border border-[#d94059]/40 bg-[#d94059]/[0.12]"
    : CARD;

  if (!onClick) {
    return <div className={`${shell} p-5`}>{body}</div>;
  }
  return (
    <button
      onClick={onClick}
      className={`${accent ? shell + " transition hover:border-[#d94059]/70 hover:bg-[#d94059]/20" : CARD_INTERACTIVE} group p-5 text-left`}
    >
      {body}
      <div className="mt-2 text-[11px] font-semibold text-white/25 transition group-hover:text-[#d94059]">
        View →
      </div>
    </button>
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
    <div className={`${CARD} p-5 ${className}`}>
      {(title || actions) && (
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            {title && (
              <h2 className="text-[15px] font-bold text-white/90">{title}</h2>
            )}
            {hint && (
              <p className="mt-1 text-xs leading-relaxed text-white/40">
                {hint}
              </p>
            )}
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
  // Capsule, tinted fill — the app's chip (WorkoutAttributionView draws its
  // pills as Capsule().fill(tint.opacity(0.18))), not a square badge.
  const cls =
    tone === "ok"
      ? "bg-[#33b34d]/20 text-[#7fe39a]"
      : tone === "bad"
        ? "bg-[#d94059]/20 text-[#ffb3c6]"
        : tone === "info"
          ? "bg-[#4099f2]/20 text-[#9ecbff]"
          : "bg-white/[0.14] text-white/60";
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[11px] font-semibold whitespace-nowrap ${cls}`}
    >
      {text}
    </span>
  );
}

/**
 * Horizontal proportional-bar list for categorical breakdowns.
 *
 * An item carrying `onClick` becomes a row you can open — the bar itself is
 * the hit target, not a separate chevron, since the whole row is the thing
 * the reader is pointing at.
 */
export function BarList({
  items,
  color = MAD_RED,
  emptyLabel = "No data yet.",
  formatValue = (v: number) => fmt(v),
}: {
  items: {
    label: string;
    value: number;
    sub?: string;
    /** Per-item colour, for lists whose rows carry their own identity
     *  (workout types, token kinds). Falls back to the list colour. */
    color?: string;
    onClick?: () => void;
  }[];
  color?: string;
  emptyLabel?: string;
  formatValue?: (v: number) => string;
}) {
  if (!items.length)
    return <p className="text-sm text-white/40">{emptyLabel}</p>;
  const max = Math.max(...items.map((i) => i.value), 1);
  return (
    <ul className="space-y-2.5">
      {items.map((it) => {
        const row = (
          <>
            <div className="mb-1 flex items-baseline justify-between gap-3 text-sm">
              <span className="truncate text-white/85">{it.label}</span>
              <span className="shrink-0 tabular-nums text-white/45">
                {it.sub ? `${it.sub} · ` : ""}
                <span className="font-semibold text-white/95">
                  {formatValue(it.value)}
                </span>
              </span>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-white/[0.06]">
              <div
                className="h-full rounded-full transition-[width] duration-300"
                style={{
                  width: `${(it.value / max) * 100}%`,
                  background: it.color ?? color,
                }}
              />
            </div>
          </>
        );
        return (
          <li key={it.label}>
            {it.onClick ? (
              <button
                onClick={it.onClick}
                className="-mx-2 block w-[calc(100%+1rem)] rounded-lg px-2 py-1 text-left transition hover:bg-white/[0.05]"
              >
                {row}
              </button>
            ) : (
              row
            )}
          </li>
        );
      })}
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
  onClick,
}: {
  label: string;
  everCount: number;
  recentCount: number;
  total: number;
  events?: number;
  /** Present = this row opens the people behind it. */
  onClick?: () => void;
}) {
  const body = (
    <>
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
              background: "#d94059",
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
    </>
  );

  return (
    <li>
      {onClick ? (
        <button
          onClick={onClick}
          className="-mx-2 block w-[calc(100%+1rem)] rounded-lg px-2 py-1 text-left transition hover:bg-white/[0.05]"
        >
          {body}
        </button>
      ) : (
        body
      )}
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
          className={`rounded-full px-3 py-1 text-xs font-semibold transition ${
            value === o.value
              ? "text-white shadow-[0_2px_8px_rgba(0,0,0,0.25)]"
              : "border border-white/[0.12] text-white/55 hover:text-white"
          }`}
          style={
            value === o.value
              ? {
                  // MADTheme.Colors.redGradient, the app's filled-pill fill.
                  background:
                    "linear-gradient(135deg, #e64d66 0%, #b3334d 100%)",
                }
              : undefined
          }
        >
          {o.label}
        </button>
      ))}
    </span>
  );
}
