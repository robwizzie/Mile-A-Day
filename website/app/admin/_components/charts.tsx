"use client";

import { useState } from "react";

export type DayPoint = { date: string; value: number };

/**
 * Reusable daily bar chart (hover for the exact value, peak marker on the
 * axis). Generalized from the original miles-by-day chart so every tab's
 * "X per day, last 30 days" reads identically.
 */
export function TimeSeriesBars({
  data,
  label,
  color = "#c72554",
  hoverColor = "#ffb3c6",
  unit = "",
  formatValue = (v: number) =>
    v.toLocaleString(undefined, { maximumFractionDigits: 1 }),
}: {
  data: DayPoint[];
  label: string;
  color?: string;
  hoverColor?: string;
  unit?: string;
  formatValue?: (v: number) => string;
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
          {unit}/day
        </span>
        <span>{data[data.length - 1]?.date}</span>
      </div>
    </div>
  );
}
