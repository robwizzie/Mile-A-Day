"use client";

import { useCallback, useEffect, useState } from "react";
import { Card, getData, Loading } from "./lib";

type ErrorRow = {
  id: string;
  category: string;
  user_id: string | null;
  username: string | null;
  message: string;
  context: Record<string, unknown> | null;
  created_at: string;
};

type ErrorTimeseriesRow = { bucket: string; series: string; count: number };
type ErrorRange = "24h" | "7d" | "30d";
type ErrorGroupBy = "category" | "user";

type UserErrorRow = {
  user_id: string | null;
  username: string | null;
  count: number;
  last_24h: number;
  last_at: string;
};

// Stable per-category colors; "total" is white. Unknown categories cycle the
// palette by first-seen order so the legend and lines always agree.
const CAT_COLORS: Record<string, string> = {
  push: "#38bdf8",
  api: "#c72554",
  auth: "#fbbf24",
};
const PALETTE = ["#a78bfa", "#34d399", "#f472b6", "#fb923c", "#60a5fa"];
function colorFor(cat: string, i: number): string {
  return CAT_COLORS[cat] ?? PALETTE[i % PALETTE.length];
}

const RANGE_BUCKETS: Record<ErrorRange, number> = {
  "24h": 24,
  "7d": 7,
  "30d": 30,
};

/** Bucket keys for the axis, UTC to match the backend's AT TIME ZONE 'UTC'
 *  keys. 24h → hourly (YYYY-MM-DDTHH); 7d/30d → daily (YYYY-MM-DD). */
function axisBuckets(range: ErrorRange): string[] {
  const n = RANGE_BUCKETS[range];
  return Array.from({ length: n }, (_, i) => {
    const d = new Date();
    if (range === "24h") {
      d.setUTCMinutes(0, 0, 0);
      d.setUTCHours(d.getUTCHours() - (n - 1 - i));
      return d.toISOString().slice(0, 13);
    }
    d.setUTCDate(d.getUTCDate() - (n - 1 - i));
    return d.toISOString().slice(0, 10);
  });
}

function fmtBucket(bucket: string, range: ErrorRange): string {
  if (range === "24h") {
    return new Date(`${bucket}:00:00Z`).toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "numeric",
    });
  }
  return bucket;
}

const MAX_LINES = 8;

/** Multi-line chart: one line per series (category, or user when grouped by
 *  user) plus a bold white "total" line. Hover shows a per-bucket tooltip;
 *  legend chips filter which series are drawn; toggle range and grouping. */
function ErrorChart({
  data,
  range,
  onRangeChange,
  groupBy,
  onGroupByChange,
}: {
  data: ErrorTimeseriesRow[];
  range: ErrorRange;
  onRangeChange: (r: ErrorRange) => void;
  groupBy: ErrorGroupBy;
  onGroupByChange: (g: ErrorGroupBy) => void;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const [hidden, setHidden] = useState<Set<string>>(new Set());

  // Different grouping = different series universe; start with all shown.
  useEffect(() => setHidden(new Set()), [groupBy]);

  const buckets = axisBuckets(range);
  const n = buckets.length;
  const bucketIndex = new Map(buckets.map((b, i) => [b, i]));

  // Raw per-series buckets, then rank by volume and cap the number of lines
  // (excess series — mostly when grouped by user — collapse into "other").
  const rawVals = new Map<string, number[]>();
  for (const r of data) {
    const i = bucketIndex.get(r.bucket);
    if (i === undefined) continue;
    if (!rawVals.has(r.series)) rawVals.set(r.series, new Array(n).fill(0));
    rawVals.get(r.series)![i] += r.count;
  }
  const sum = (a: number[]) => a.reduce((s, v) => s + v, 0);
  const ranked = [...rawVals.keys()].sort(
    (a, b) => sum(rawVals.get(b)!) - sum(rawVals.get(a)!),
  );
  const display = ranked.slice(0, MAX_LINES).map((k, idx) => ({
    key: k,
    color: colorFor(k, idx),
    vals: rawVals.get(k)!,
  }));
  const rest = ranked.slice(MAX_LINES);
  if (rest.length) {
    const other = new Array(n).fill(0);
    for (const k of rest) rawVals.get(k)!.forEach((v, i) => (other[i] += v));
    display.push({ key: "other", color: "#9ca3af", vals: other });
  }

  const visible = display.filter((d) => !hidden.has(d.key));
  const total = buckets.map((_, i) =>
    visible.reduce((s, d) => s + d.vals[i], 0),
  );
  const max = Math.max(...total, 1);

  const W = 720;
  const H = 200;
  const x = (i: number) => (n > 1 ? (i / (n - 1)) * W : W / 2);
  const y = (v: number) => H - (v / max) * (H - 10);
  const path = (vals: number[]) =>
    vals.map((v, i) => `${i === 0 ? "M" : "L"}${x(i)},${y(v)}`).join(" ");

  const lines = [
    ...visible.map((d) => ({ ...d, width: 1.5 })),
    { key: "total", color: "#ffffff", vals: total, width: 2.5 },
  ];

  function toggle(key: string) {
    setHidden((prev) => {
      const next = new Set(prev);
      if (!next.delete(key)) next.add(key);
      return next;
    });
  }

  // Tooltip horizontal placement, clamped so it doesn't clip at the edges.
  const p = hover === null ? 0 : n > 1 ? hover / (n - 1) : 0.5;
  const tipX = p < 0.15 ? "0%" : p > 0.85 ? "-100%" : "-50%";
  const tipRows =
    hover === null
      ? []
      : visible
          .filter((d) => d.vals[hover] > 0)
          .sort((a, b) => b.vals[hover] - a.vals[hover]);

  const RANGES: ErrorRange[] = ["24h", "7d", "30d"];
  const GROUPS: ErrorGroupBy[] = ["category", "user"];

  return (
    <div className="mb-6 rounded-xl border border-white/10 bg-white/[0.03] p-5">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2 text-sm font-medium text-white/70">
        <span className="flex items-center gap-2">
          <span>Errors by</span>
          <span className="flex gap-1">
            {GROUPS.map((g) => (
              <button
                key={g}
                onClick={() => onGroupByChange(g)}
                className={`rounded-full px-2.5 py-0.5 text-xs ${
                  groupBy === g
                    ? "bg-[#c72554] text-white"
                    : "border border-white/10 text-white/60"
                }`}
              >
                {g}
              </button>
            ))}
          </span>
        </span>
        <span className="flex gap-1">
          {RANGES.map((r) => (
            <button
              key={r}
              onClick={() => onRangeChange(r)}
              className={`rounded-full px-2.5 py-0.5 text-xs ${
                range === r
                  ? "bg-[#c72554] text-white"
                  : "border border-white/10 text-white/60"
              }`}
            >
              {r}
            </button>
          ))}
        </span>
      </div>

      <div className="relative">
        <svg
          viewBox={`0 0 ${W} ${H}`}
          className="h-52 w-full overflow-visible"
          role="img"
          aria-label={`Error counts by ${groupBy} over the last ${range}`}
          onMouseLeave={() => setHover(null)}
        >
          {lines.map((l) => (
            <path
              key={l.key}
              d={path(l.vals)}
              fill="none"
              stroke={l.color}
              strokeWidth={l.width}
              strokeLinejoin="round"
              opacity={l.key === "total" ? 0.9 : 0.85}
            />
          ))}
          {hover !== null && (
            <line
              x1={x(hover)}
              x2={x(hover)}
              y1={0}
              y2={H}
              stroke="white"
              strokeOpacity={0.2}
            />
          )}
          {/* Invisible per-bucket hit columns drive the hover readout. */}
          {buckets.map((b, i) => (
            <rect
              key={b}
              x={x(i) - W / (2 * n)}
              y={0}
              width={W / n}
              height={H}
              fill="transparent"
              onMouseEnter={() => setHover(i)}
            />
          ))}
        </svg>

        {hover !== null && (
          <div
            className="pointer-events-none absolute top-0 z-10 w-max max-w-[240px]"
            style={{ left: `${p * 100}%`, transform: `translateX(${tipX})` }}
          >
            <div className="rounded-md border border-white/10 bg-black/85 px-2.5 py-1.5 text-xs shadow-lg">
              <div className="mb-1 text-white/50">
                {fmtBucket(buckets[hover], range)}
              </div>
              {tipRows.length === 0 ? (
                <div className="text-white/40">0 errors</div>
              ) : (
                tipRows.map((d) => (
                  <div
                    key={d.key}
                    className="flex items-center justify-between gap-3"
                  >
                    <span className="flex items-center gap-1.5 text-white/70">
                      <span
                        className="inline-block h-2 w-2 rounded-sm"
                        style={{ background: d.color }}
                      />
                      {d.key}
                    </span>
                    <span className="text-white/90">{d.vals[hover]}</span>
                  </div>
                ))
              )}
              <div className="mt-1 flex items-center justify-between gap-3 border-t border-white/10 pt-1 text-white/80">
                <span>Total</span>
                <span>{total[hover]}</span>
              </div>
            </div>
          </div>
        )}
      </div>

      <div className="mt-3 flex flex-wrap gap-x-3 gap-y-1 text-xs">
        {display.map((d) => {
          const off = hidden.has(d.key);
          return (
            <button
              key={d.key}
              onClick={() => toggle(d.key)}
              className={`flex items-center gap-1.5 ${off ? "opacity-40" : "text-white/60"}`}
            >
              <span
                className="inline-block h-2 w-3 rounded-sm"
                style={{ background: d.color }}
              />
              <span className={off ? "line-through" : ""}>{d.key}</span>
              <span className="text-white/40">
                {hover !== null ? d.vals[hover] : sum(d.vals)}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

/** Which user each error is attached to (for push errors that's the
 *  recipient). Click a user to load and inspect their individual errors. */
export function ErrorsTab() {
  const [users, setUsers] = useState<UserErrorRow[] | null>(null);
  const [series, setSeries] = useState<ErrorTimeseriesRow[]>([]);
  const [range, setRange] = useState<ErrorRange>("7d");
  const [groupBy, setGroupBy] = useState<ErrorGroupBy>("category");
  const [open, setOpen] = useState<string | null>(null);
  const [rows, setRows] = useState<ErrorRow[]>([]);
  const [rowsLoading, setRowsLoading] = useState(false);

  const load = useCallback(async () => {
    try {
      setUsers(await getData<UserErrorRow[]>("errors/by-user"));
    } catch {
      /* unauthorized handled in getData */
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // Chart series refetch whenever the range or grouping toggle changes.
  useEffect(() => {
    getData<ErrorTimeseriesRow[]>(
      `errors/timeseries?range=${range}&groupBy=${groupBy}`,
    )
      .then(setSeries)
      .catch(() => {
        /* unauthorized handled in getData */
      });
  }, [range, groupBy]);

  async function toggle(userId: string) {
    if (open === userId) {
      setOpen(null);
      return;
    }
    setOpen(userId);
    setRowsLoading(true);
    try {
      setRows(
        await getData<ErrorRow[]>(
          `errors?limit=200&userId=${encodeURIComponent(userId)}`,
        ),
      );
    } catch {
      setRows([]);
    } finally {
      setRowsLoading(false);
    }
  }

  const label = (u: UserErrorRow) =>
    u.username ? `@${u.username}` : u.user_id ? u.user_id : "(no user)";

  return (
    <>
      <ErrorChart
        data={series}
        range={range}
        onRangeChange={setRange}
        groupBy={groupBy}
        onGroupByChange={setGroupBy}
      />

      <Card
        title="Errors by user"
        actions={
          <button
            onClick={load}
            className="rounded-md border border-white/10 px-2 py-1 text-xs text-white/60 hover:text-white"
          >
            Refresh
          </button>
        }
      >
        {!users ? (
          <Loading />
        ) : users.length === 0 ? (
          <p className="text-sm text-white/40">No errors logged. 🎉</p>
        ) : (
          <ul className="divide-y divide-white/5">
            {users.map((u) => {
              const id = u.user_id;
              const isOpen = open === id;
              return (
                <li key={id ?? "none"} className="py-2">
                  <button
                    onClick={() => id && toggle(id)}
                    disabled={!id}
                    className="flex w-full items-center justify-between text-left disabled:cursor-default"
                  >
                    <span className="text-sm text-white/90">{label(u)}</span>
                    <span className="flex items-center gap-2 text-xs text-white/50">
                      {u.last_24h > 0 && (
                        <span className="text-[#ffb3c6]">
                          {u.last_24h} today
                        </span>
                      )}
                      <span className="rounded bg-white/10 px-1.5 py-0.5 text-white/70">
                        {u.count}
                      </span>
                    </span>
                  </button>

                  {isOpen && (
                    <div className="mt-2 pl-2">
                      {rowsLoading ? (
                        <p className="text-xs text-white/40">Loading…</p>
                      ) : (
                        <ul className="divide-y divide-white/5">
                          {rows.map((r) => (
                            <li key={r.id} className="py-2">
                              <details>
                                <summary className="cursor-pointer list-none">
                                  <span className="mr-2 rounded bg-white/10 px-1.5 py-0.5 text-xs text-white/70">
                                    {r.category}
                                  </span>
                                  <span className="text-sm text-white/90">
                                    {r.message}
                                  </span>
                                  <span className="ml-2 text-xs text-white/40">
                                    {new Date(r.created_at).toLocaleString()}
                                  </span>
                                </summary>
                                <pre className="mt-2 overflow-x-auto rounded bg-black/40 p-3 text-xs text-white/60">
                                  {JSON.stringify(r.context, null, 2)}
                                </pre>
                              </details>
                            </li>
                          ))}
                        </ul>
                      )}
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </Card>
    </>
  );
}
