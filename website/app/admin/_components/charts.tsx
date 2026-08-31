"use client";

import { Fragment, useState } from "react";

export type DayPoint = { date: string; value: number };

/**
 * Reusable daily bar chart (hover for the exact value, peak marker on the
 * axis). Generalized from the original miles-by-day chart so every tab's
 * "X per day, last 30 days" reads identically.
 */
export function TimeSeriesBars({
  data,
  label,
  color = "#d94059",
  hoverColor = "#ffb3c6",
  unit = "",
  formatValue = (v: number) =>
    v.toLocaleString(undefined, { maximumFractionDigits: 1 }),
  period = "day",
}: {
  data: DayPoint[];
  label: string;
  color?: string;
  hoverColor?: string;
  unit?: string;
  formatValue?: (v: number) => string;
  /** What one bar covers. The axis says "peak N/<period>", so a weekly
   *  series left on the default claimed a daily peak it never measured. */
  period?: string;
}) {
  const [hover, setHover] = useState<DayPoint | null>(null);
  if (!data.length)
    return (
      <div>
        <div className="mb-3 text-sm font-medium text-white/70">{label}</div>
        <p className="text-sm text-white/40">No data yet.</p>
      </div>
    );
  const max = Math.max(...data.map((d) => d.value), 1);
  const total = data.reduce((s, d) => s + d.value, 0);
  const W = 720;
  const H = 180;
  const gap = 3;
  const barW = (W - gap * (data.length - 1)) / data.length;
  return (
    <div>
      <div className="mb-3 flex items-baseline justify-between text-sm font-medium text-white/70">
        <span>{label}</span>
        {hover ? (
          <span className="text-white/90">
            {hover.date}:{" "}
            <span style={{ color: hoverColor }}>
              {formatValue(hover.value)}
              {unit}
            </span>
          </span>
        ) : (
          <span className="text-xs text-white/40">
            {formatValue(total)}
            {unit} total
          </span>
        )}
      </div>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="h-44 w-full"
        role="img"
        aria-label={label}
      >
        {data.map((d, i) => {
          const h = (d.value / max) * (H - 20);
          return (
            <rect
              key={d.date}
              x={i * (barW + gap)}
              y={H - h}
              width={barW}
              height={Math.max(h, d.value > 0 ? 1 : 0)}
              rx={2}
              fill={hover?.date === d.date ? hoverColor : color}
              onMouseEnter={() => setHover(d)}
              onMouseLeave={() => setHover(null)}
            >
              <title>{`${d.date}: ${formatValue(d.value)}${unit}`}</title>
            </rect>
          );
        })}
      </svg>
      <div className="mt-2 flex justify-between text-xs text-white/40">
        <span>{data[0]?.date}</span>
        <span>
          peak {formatValue(max)}
          {unit}/{period}
        </span>
        <span>{data[data.length - 1]?.date}</span>
      </div>
    </div>
  );
}

/**
 * Stacked daily bars for a few series that share one unit and one axis.
 *
 * The stack is only honest because every series counts the same thing (a
 * streak token spent) — two different units would need two charts, never a
 * second y-scale. Series colors come from lib's SERIES set, assigned in fixed
 * order so a series keeps its color when another is empty, and the legend is
 * always drawn: identity is never carried by color alone.
 */
export function StackedDayBars<K extends string>({
  data,
  series,
  label,
  hint,
}: {
  data: (Record<K, number> & { date: string })[];
  series: { key: K; label: string; color: string }[];
  label: string;
  hint?: string;
}) {
  const [hover, setHover] = useState<string | null>(null);

  const totals = data.map((d) =>
    series.reduce((sum, s) => sum + (d[s.key] || 0), 0),
  );
  const max = Math.max(...totals, 1);
  const grandTotal = totals.reduce((a, b) => a + b, 0);
  const hovered = hover ? data.find((d) => d.date === hover) : null;

  const W = 720;
  const H = 160;
  const gap = 3;
  // 2px of surface between stacked segments, per the mark spec — without it
  // two adjacent counts read as one taller block.
  const SEG_GAP = 2;
  const barW = (W - gap * (data.length - 1)) / data.length;

  return (
    <div>
      <div className="mb-1 flex items-baseline justify-between gap-3 text-sm font-medium text-white/70">
        <span>{label}</span>
        {hovered ? (
          <span className="text-xs text-white/80">
            {hovered.date} ·{" "}
            {series
              .filter((s) => hovered[s.key] > 0)
              .map((s) => `${hovered[s.key]} ${s.label}`)
              .join(", ") || "none"}
          </span>
        ) : (
          <span className="text-xs text-white/40">{grandTotal} in 30 days</span>
        )}
      </div>
      {hint && <p className="mb-2 text-xs text-white/40">{hint}</p>}

      {grandTotal === 0 ? (
        <p className="py-8 text-sm text-white/40">
          Nothing spent in the last 30 days.
        </p>
      ) : (
        <svg
          viewBox={`0 0 ${W} ${H}`}
          className="h-40 w-full"
          role="img"
          aria-label={label}
        >
          {data.map((d, i) => {
            const total = totals[i];
            let y = H;
            return (
              <g
                key={d.date}
                onMouseEnter={() => setHover(d.date)}
                onMouseLeave={() => setHover(null)}
              >
                {/* Full-height hit target: a 1px bar is impossible to hover. */}
                <rect
                  x={i * (barW + gap)}
                  y={0}
                  width={barW + gap}
                  height={H}
                  fill="transparent"
                />
                {series.map((s, si) => {
                  const v = d[s.key] || 0;
                  if (!v) return null;
                  const h = (v / max) * (H - 12);
                  y -= h;
                  const top = si === series.length - 1 || y === H - h;
                  const rect = (
                    <rect
                      key={s.key}
                      x={i * (barW + gap)}
                      y={y}
                      width={barW}
                      height={Math.max(h - SEG_GAP, 1)}
                      rx={top ? 3 : 1}
                      fill={s.color}
                      opacity={hover && hover !== d.date ? 0.35 : 1}
                    >
                      <title>{`${d.date}: ${v} ${s.label}`}</title>
                    </rect>
                  );
                  y -= SEG_GAP;
                  return rect;
                })}
                {total === 0 && null}
              </g>
            );
          })}
        </svg>
      )}

      <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-white/40">
        {series.map((s) => (
          <span key={s.key} className="flex items-center gap-1.5">
            <span
              className="h-2 w-2 rounded-sm"
              style={{ background: s.color }}
              aria-hidden
            />
            {s.label}
          </span>
        ))}
        <span className="ml-auto">
          {data[0]?.date} → {data[data.length - 1]?.date}
        </span>
      </div>
    </div>
  );
}

/**
 * Sequential heat grid — one hue, intensity rising with magnitude.
 *
 * On a dark surface "light → dark" runs the other way: a cell's alpha over
 * the card is what encodes the value, which keeps the ramp monotone in one
 * hue by construction. Zero is drawn as the empty surface, never as the
 * palest step, so "nobody ran at 4am" and "one person did" don't look alike.
 */
export function HeatGrid({
  rows,
  cols,
  value,
  title,
  hue = "199, 37, 84",
  formatValue = (v: number) => String(v),
  colLabel,
  legend,
  cell = 20,
  onRowClick,
}: {
  rows: { key: string; label: string }[];
  cols: { key: string; label: string }[];
  value: (rowKey: string, colKey: string) => number | null;
  title: (rowLabel: string, colLabel: string, v: number) => string;
  /** Comma-separated RGB of the single sequential hue. */
  hue?: string;
  formatValue?: (v: number) => string;
  colLabel?: (col: { key: string; label: string }, i: number) => boolean;
  legend?: string;
  /** Column width in px. FIXED, never 1fr — see the header note below. */
  cell?: number;
  /** Present = a row label opens the rows behind that row. */
  onRowClick?: (rowKey: string) => void;
}) {
  let max = 0;
  for (const r of rows)
    for (const c of cols) {
      const v = value(r.key, c.key);
      if (v != null && v > max) max = v;
    }

  return (
    <div className="overflow-x-auto">
      <div className="min-w-max">
        <div
          className="grid gap-[2px]"
          style={{
            gridTemplateColumns: `auto repeat(${cols.length}, ${cell}px)`,
            justifyContent: "start",
          }}
        >
          <div />
          {/* Header labels are absolutely positioned inside a zero-width
              anchor. A label placed in the flow is wider than its column, so
              the tracks carrying one grow and the axis silently drifts out of
              alignment with the cells beneath it. */}
          {cols.map((c, i) => (
            <div key={c.key} className="relative h-4">
              {(!colLabel || colLabel(c, i)) && (
                <span className="absolute left-1/2 -translate-x-1/2 text-[10px] whitespace-nowrap text-white/30">
                  {c.label}
                </span>
              )}
            </div>
          ))}
          {rows.map((r) => (
            <Fragment key={r.key}>
              {onRowClick ? (
                <button
                  onClick={() => onRowClick(r.key)}
                  className="pr-2 text-right text-[11px] whitespace-nowrap text-white/40 transition hover:text-white"
                  style={{ lineHeight: `${cell}px` }}
                >
                  {r.label}
                </button>
              ) : (
                <div
                  className="pr-2 text-right text-[11px] whitespace-nowrap text-white/40"
                  style={{ lineHeight: `${cell}px` }}
                >
                  {r.label}
                </div>
              )}
              {cols.map((c) => {
                const v = value(r.key, c.key);
                if (v == null)
                  return (
                    <div
                      key={c.key}
                      className="rounded-[3px]"
                      style={{ height: cell }}
                    />
                  );
                // 0 stays as bare surface; anything above it starts at a
                // visible step so the first unit is never invisible.
                const t = max ? v / max : 0;
                const alpha = v === 0 ? 0 : 0.18 + t * 0.82;
                return (
                  <div
                    key={c.key}
                    title={title(r.label, c.label, v)}
                    className="rounded-[3px] border border-white/[0.04]"
                    style={{ height: cell, background: `rgba(${hue}, ${alpha})` }}
                  />
                );
              })}
            </Fragment>
          ))}
        </div>
        <div className="mt-2 flex items-center gap-2 text-[11px] text-white/40">
          {legend && <span>{legend}</span>}
          <span className="ml-auto flex items-center gap-1">
            0
            {[0.18, 0.4, 0.62, 0.84, 1].map((a) => (
              <span
                key={a}
                className="h-2.5 w-4 rounded-[2px]"
                style={{ background: `rgba(${hue}, ${a})` }}
                aria-hidden
              />
            ))}
            {formatValue(max)}
          </span>
        </div>
      </div>
    </div>
  );
}
