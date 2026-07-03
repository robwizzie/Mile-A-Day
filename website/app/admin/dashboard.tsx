"use client";

import { useCallback, useEffect, useState } from "react";

type Overview = {
  total_users: number;
  total_miles: number;
  miles_today: number;
  active_users_7d: number;
  total_hypes: number;
  hypes_today: number;
  total_nudges: number;
  nudges_today: number;
};

type DayMiles = { date: string; miles: number };

type ErrorRow = {
  id: string;
  category: string;
  user_id: string | null;
  message: string;
  context: Record<string, unknown> | null;
  created_at: string;
};

type ErrorSummary = {
  total: number;
  byCategory: { category: string; count: number; last_24h: number }[];
};

async function getData<T>(path: string): Promise<T> {
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

const fmt = (n: number) =>
  n >= 1000
    ? n.toLocaleString(undefined, { maximumFractionDigits: 0 })
    : String(n);

function StatCard({
  label,
  value,
  sub,
}: {
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.03] p-5">
      <div className="text-xs uppercase tracking-wide text-white/40">
        {label}
      </div>
      <div className="mt-1 text-3xl font-semibold text-white">{value}</div>
      {sub && <div className="mt-1 text-sm text-white/50">{sub}</div>}
    </div>
  );
}

function MilesChart({ data }: { data: DayMiles[] }) {
  if (!data.length) return null;
  const max = Math.max(...data.map((d) => d.miles), 1);
  const W = 720;
  const H = 180;
  const gap = 3;
  const barW = (W - gap * (data.length - 1)) / data.length;
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.03] p-5">
      <div className="mb-3 text-sm font-medium text-white/70">
        Miles by day — last 30 days
      </div>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="h-44 w-full"
        role="img"
        aria-label="Total miles per day over the last 30 days"
      >
        {data.map((d, i) => {
          const h = (d.miles / max) * (H - 20);
          return (
            <rect
              key={d.date}
              x={i * (barW + gap)}
              y={H - h}
              width={barW}
              height={h}
              rx={2}
              fill="#c72554"
            >
              <title>{`${d.date}: ${d.miles.toFixed(1)} mi`}</title>
            </rect>
          );
        })}
      </svg>
      <div className="mt-2 flex justify-between text-xs text-white/40">
        <span>{data[0]?.date}</span>
        <span>peak {max.toFixed(0)} mi/day</span>
        <span>{data[data.length - 1]?.date}</span>
      </div>
    </div>
  );
}

function ErrorList() {
  const [summary, setSummary] = useState<ErrorSummary | null>(null);
  const [rows, setRows] = useState<ErrorRow[]>([]);
  const [category, setCategory] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [s, r] = await Promise.all([
        getData<ErrorSummary>("errors/summary"),
        getData<ErrorRow[]>(
          `errors?limit=100${category ? `&category=${encodeURIComponent(category)}` : ""}`,
        ),
      ]);
      setSummary(s);
      setRows(r);
    } catch {
      /* unauthorized handled in getData */
    } finally {
      setLoading(false);
    }
  }, [category]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.03] p-5">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-sm font-medium text-white/70">
          Errors {summary ? `(${summary.total})` : ""}
        </h2>
        <button
          onClick={load}
          className="rounded-md border border-white/10 px-2 py-1 text-xs text-white/60 hover:text-white"
        >
          Refresh
        </button>
      </div>

      <div className="mb-4 flex flex-wrap gap-2">
        <button
          onClick={() => setCategory(null)}
          className={`rounded-full px-3 py-1 text-xs ${category === null ? "bg-[#c72554] text-white" : "border border-white/10 text-white/60"}`}
        >
          all
        </button>
        {summary?.byCategory.map((c) => (
          <button
            key={c.category}
            onClick={() => setCategory(c.category)}
            className={`rounded-full px-3 py-1 text-xs ${category === c.category ? "bg-[#c72554] text-white" : "border border-white/10 text-white/60"}`}
          >
            {c.category} {c.count}
            {c.last_24h > 0 && (
              <span className="ml-1 text-[#ffb3c6]">·{c.last_24h} today</span>
            )}
          </button>
        ))}
      </div>

      {loading ? (
        <p className="text-sm text-white/40">Loading…</p>
      ) : rows.length === 0 ? (
        <p className="text-sm text-white/40">No errors logged. 🎉</p>
      ) : (
        <ul className="divide-y divide-white/5">
          {rows.map((r) => (
            <li key={r.id} className="py-3">
              <details>
                <summary className="cursor-pointer list-none">
                  <span className="mr-2 rounded bg-white/10 px-1.5 py-0.5 text-xs text-white/70">
                    {r.category}
                  </span>
                  <span className="text-sm text-white/90">{r.message}</span>
                  <span className="ml-2 text-xs text-white/40">
                    {new Date(r.created_at).toLocaleString()}
                  </span>
                </summary>
                <pre className="mt-2 overflow-x-auto rounded bg-black/40 p-3 text-xs text-white/60">
                  {JSON.stringify(
                    { user_id: r.user_id, context: r.context },
                    null,
                    2,
                  )}
                </pre>
              </details>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function AdminDashboard() {
  const [overview, setOverview] = useState<Overview | null>(null);
  const [miles, setMiles] = useState<DayMiles[]>([]);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      getData<Overview>("overview"),
      getData<DayMiles[]>("miles-by-day"),
    ])
      .then(([o, m]) => {
        setOverview(o);
        setMiles(m);
      })
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load dashboard");
      });
  }, []);

  async function logout() {
    await fetch("/admin/api/logout", { method: "POST" });
    window.location.reload();
  }

  return (
    <main className="min-h-screen bg-[#0a0a0a] px-6 py-10 text-white">
      <div className="mx-auto max-w-5xl">
        <div className="mb-8 flex items-center justify-between">
          <h1 className="text-2xl font-semibold">Mile A Day — Admin</h1>
          <button
            onClick={logout}
            className="rounded-lg border border-white/10 px-3 py-1.5 text-sm text-white/60 hover:text-white"
          >
            Sign out
          </button>
        </div>

        {err && <p className="mb-6 text-sm text-[#c72554]">{err}</p>}

        {overview && (
          <div className="mb-6 grid grid-cols-2 gap-4 md:grid-cols-4">
            <StatCard label="Total users" value={fmt(overview.total_users)} />
            <StatCard
              label="Active (7d)"
              value={fmt(overview.active_users_7d)}
            />
            <StatCard
              label="Total miles"
              value={fmt(Math.round(overview.total_miles))}
              sub={`${overview.miles_today.toFixed(1)} today`}
            />
            <StatCard
              label="Miles today"
              value={overview.miles_today.toFixed(1)}
            />
            <StatCard
              label="Hypes"
              value={fmt(overview.total_hypes)}
              sub={`${overview.hypes_today} today`}
            />
            <StatCard
              label="Nudges"
              value={fmt(overview.total_nudges)}
              sub={`${overview.nudges_today} today`}
            />
          </div>
        )}

        <div className="mb-6">
          <MilesChart data={miles} />
        </div>

        <ErrorList />
      </div>
    </main>
  );
}
