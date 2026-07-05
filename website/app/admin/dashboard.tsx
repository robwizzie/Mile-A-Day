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
  username: string | null;
  message: string;
  context: Record<string, unknown> | null;
  created_at: string;
};

type ErrorTimeseriesRow = { date: string; category: string; count: number };

type UserErrorRow = {
  user_id: string | null;
  username: string | null;
  count: number;
  last_24h: number;
  last_at: string;
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

/** POST an admin action; surfaces the backend's error message on failure. */
async function postData<T>(path: string): Promise<T> {
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
function mediaSrc(url: string): string {
  if (url.startsWith("/")) {
    return `${process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech"}${url}`;
  }
  return url;
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
  const [hover, setHover] = useState<DayMiles | null>(null);
  if (!data.length) return null;
  const max = Math.max(...data.map((d) => d.miles), 1);
  const W = 720;
  const H = 180;
  const gap = 3;
  const barW = (W - gap * (data.length - 1)) / data.length;
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.03] p-5">
      <div className="mb-3 flex items-baseline justify-between text-sm font-medium text-white/70">
        <span>Miles by day — last 30 days</span>
        {hover && (
          <span className="text-white/90">
            {hover.date}:{" "}
            <span className="text-[#ffb3c6]">{hover.miles.toFixed(1)} mi</span>
          </span>
        )}
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
              fill={hover?.date === d.date ? "#ffb3c6" : "#c72554"}
              onMouseEnter={() => setHover(d)}
              onMouseLeave={() => setHover(null)}
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

/** Multi-line chart: one line per error category plus a bold white "total"
 *  line. Hover a day to read every series' value for that day. */
function ErrorChart({ data }: { data: ErrorTimeseriesRow[] }) {
  const [hover, setHover] = useState<number | null>(null);

  // 30-day axis ending today, zero-filled so lines stay continuous.
  const days = Array.from({ length: 30 }, (_, i) => {
    const d = new Date();
    d.setDate(d.getDate() - (29 - i));
    return d.toISOString().slice(0, 10);
  });
  const dayIndex = new Map(days.map((d, i) => [d, i]));

  const cats = Array.from(new Set(data.map((r) => r.category))).sort();
  const series = new Map<string, number[]>(
    cats.map((c) => [c, new Array(30).fill(0)]),
  );
  for (const r of data) {
    const i = dayIndex.get(r.date);
    if (i !== undefined) series.get(r.category)![i] += r.count;
  }
  const total = days.map((_, i) =>
    cats.reduce((s, c) => s + series.get(c)![i], 0),
  );
  const max = Math.max(...total, 1);

  const W = 720;
  const H = 200;
  const x = (i: number) => (i / 29) * W;
  const y = (v: number) => H - (v / max) * (H - 10);
  const path = (vals: number[]) =>
    vals.map((v, i) => `${i === 0 ? "M" : "L"}${x(i)},${y(v)}`).join(" ");

  const lines = [
    ...cats.map((c, i) => ({
      key: c,
      color: colorFor(c, i),
      vals: series.get(c)!,
      width: 1.5,
    })),
    { key: "total", color: "#ffffff", vals: total, width: 2.5 },
  ];

  return (
    <div className="mb-6 rounded-xl border border-white/10 bg-white/[0.03] p-5">
      <div className="mb-3 flex items-baseline justify-between text-sm font-medium text-white/70">
        <span>Errors by day — last 30 days</span>
        {hover !== null && (
          <span className="text-xs text-white/60">{days[hover]}</span>
        )}
      </div>

      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="h-52 w-full overflow-visible"
        role="img"
        aria-label="Error counts per day by category over the last 30 days"
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
        {/* Invisible per-day hit columns drive the hover readout. */}
        {days.map((d, i) => (
          <rect
            key={d}
            x={x(i) - W / 60}
            y={0}
            width={W / 30}
            height={H}
            fill="transparent"
            onMouseEnter={() => setHover(i)}
          />
        ))}
      </svg>

      <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs">
        {lines.map((l) => (
          <span key={l.key} className="flex items-center gap-1.5 text-white/60">
            <span
              className="inline-block h-2 w-3 rounded-sm"
              style={{ background: l.color }}
            />
            {l.key}
            <span className="text-white/40">
              {hover !== null
                ? l.vals[hover]
                : l.vals.reduce((s, v) => s + v, 0)}
            </span>
          </span>
        ))}
      </div>
    </div>
  );
}

/** Which user each error is attached to (for push errors that's the
 *  recipient). Click a user to load and inspect their individual errors. */
function ErrorsByUser() {
  const [users, setUsers] = useState<UserErrorRow[] | null>(null);
  const [series, setSeries] = useState<ErrorTimeseriesRow[]>([]);
  const [open, setOpen] = useState<string | null>(null);
  const [rows, setRows] = useState<ErrorRow[]>([]);
  const [rowsLoading, setRowsLoading] = useState(false);

  const load = useCallback(async () => {
    try {
      const [u, s] = await Promise.all([
        getData<UserErrorRow[]>("errors/by-user"),
        getData<ErrorTimeseriesRow[]>("errors/timeseries"),
      ]);
      setUsers(u);
      setSeries(s);
    } catch {
      /* unauthorized handled in getData */
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

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
      {series.length > 0 && <ErrorChart data={series} />}

      <div className="rounded-xl border border-white/10 bg-white/[0.03] p-5">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-medium text-white/70">Errors by user</h2>
          <button
            onClick={load}
            className="rounded-md border border-white/10 px-2 py-1 text-xs text-white/60 hover:text-white"
          >
            Refresh
          </button>
        </div>

        {!users ? (
          <p className="text-sm text-white/40">Loading…</p>
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
      </div>
    </>
  );
}

type ForensicsPost = {
  post_id: string;
  workout_id: string | null;
  media_url: string;
  caption: string | null;
  is_auto: boolean;
  share_to_feed: boolean;
  share_to_story: boolean;
  local_date: string;
  created_at: string;
  deleted_at: string | null;
  workout_type: string | null;
  workout_distance: number | null;
  media_file: string | null;
  media_file_exists: boolean | null;
};

function Chip({ text, tone }: { text: string; tone: "ok" | "bad" | "muted" }) {
  const cls =
    tone === "ok"
      ? "bg-emerald-500/15 text-emerald-300"
      : tone === "bad"
        ? "bg-[#c72554]/20 text-[#ffb3c6]"
        : "bg-white/10 text-white/60";
  return (
    <span className={`rounded px-1.5 py-0.5 text-[11px] font-medium ${cls}`}>
      {text}
    </span>
  );
}

/**
 * "My photo disappeared" investigator: every posts row for a user (soft-
 * deleted included) with what the media file's fate on disk is, a viewable
 * thumbnail, and one-tap restore for deleted rows. Defaults to the signed-in
 * admin's own posts so it works without knowing any ids — phone-friendly.
 */
function PhotoForensics() {
  const today = new Date().toISOString().slice(0, 10);
  const [userId, setUserId] = useState("me");
  const [from, setFrom] = useState("2026-07-01");
  const [to, setTo] = useState(today);
  const [rows, setRows] = useState<ForensicsPost[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  const load = useCallback(async () => {
    setBusy(true);
    setNote(null);
    try {
      const r = await getData<{ posts: ForensicsPost[] }>(
        `posts/${encodeURIComponent(userId.trim() || "me")}/forensics?from=${from}&to=${to}`,
      );
      setRows(r.posts);
      if (r.posts.length === 0) setNote("No posts in this window.");
    } catch (e) {
      if ((e as Error)?.message !== "unauthorized")
        setNote("Failed to load posts.");
    } finally {
      setBusy(false);
    }
  }, [userId, from, to]);

  async function restore(id: string) {
    setBusy(true);
    setNote(null);
    try {
      await postData<{ ok: boolean }>(`posts/${id}/restore`);
      setNote("Restored — the post is live again.");
      await load();
    } catch (e) {
      if ((e as Error)?.message !== "unauthorized")
        setNote(`Restore failed: ${(e as Error).message}`);
      setBusy(false);
    }
  }

  return (
    <div className="mb-6 rounded-xl border border-white/10 bg-white/[0.03] p-5">
      <h2 className="mb-1 text-sm font-medium text-white/70">
        Photo forensics
      </h2>
      <p className="mb-4 text-xs text-white/40">
        Every post in the window, including deleted ones. FILE OK means the
        image still exists on the server — restoring a deleted row brings the
        photo back everywhere.
      </p>

      <div className="mb-4 flex flex-wrap items-end gap-3">
        <label className="text-xs text-white/50">
          User id (or “me”)
          <input
            value={userId}
            onChange={(e) => setUserId(e.target.value)}
            className="mt-1 block w-40 rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-sm text-white"
          />
        </label>
        <label className="text-xs text-white/50">
          From
          <input
            type="date"
            value={from}
            onChange={(e) => setFrom(e.target.value)}
            className="mt-1 block rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-sm text-white"
          />
        </label>
        <label className="text-xs text-white/50">
          To
          <input
            type="date"
            value={to}
            onChange={(e) => setTo(e.target.value)}
            className="mt-1 block rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-sm text-white"
          />
        </label>
        <button
          onClick={load}
          disabled={busy}
          className="rounded-lg bg-[#c72554] px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
        >
          {busy ? "Working…" : "Load posts"}
        </button>
      </div>

      {note && <p className="mb-3 text-sm text-white/60">{note}</p>}

      {rows && rows.length > 0 && (
        <ul className="divide-y divide-white/5">
          {rows.map((p) => (
            <li key={p.post_id} className="flex gap-3 py-3">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={mediaSrc(p.media_url)}
                alt=""
                className="h-20 w-16 shrink-0 rounded-md border border-white/10 object-cover"
                onError={(e) => {
                  (e.target as HTMLImageElement).style.opacity = "0.25";
                }}
              />
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-1.5">
                  <span className="text-sm text-white/90">{p.local_date}</span>
                  {p.workout_type && (
                    <span className="text-xs text-white/50">
                      {p.workout_type}
                      {p.workout_distance != null
                        ? ` · ${p.workout_distance.toFixed(2)} mi`
                        : ""}
                    </span>
                  )}
                </div>
                <div className="mt-1 flex flex-wrap gap-1.5">
                  {p.share_to_feed && <Chip text="FEED" tone="muted" />}
                  {p.share_to_story && <Chip text="STORY" tone="muted" />}
                  {p.is_auto && <Chip text="AUTO CARD" tone="muted" />}
                  {p.deleted_at ? (
                    <Chip
                      text={`DELETED ${new Date(p.deleted_at).toLocaleString()}`}
                      tone="bad"
                    />
                  ) : (
                    <Chip text="LIVE" tone="ok" />
                  )}
                  {p.media_file_exists === true && (
                    <Chip text="FILE OK" tone="ok" />
                  )}
                  {p.media_file_exists === false && (
                    <Chip text="FILE GONE" tone="bad" />
                  )}
                </div>
                {p.caption && (
                  <p className="mt-1 truncate text-xs text-white/50">
                    “{p.caption}”
                  </p>
                )}
                {p.media_file && (
                  <p className="mt-1 select-all font-mono text-[11px] text-white/35">
                    {p.media_file}
                  </p>
                )}
                {p.deleted_at && (
                  <button
                    onClick={() => restore(p.post_id)}
                    disabled={busy}
                    className="mt-2 rounded-md border border-emerald-400/40 px-3 py-1 text-xs font-medium text-emerald-300 disabled:opacity-50"
                  >
                    Restore this post
                  </button>
                )}
              </div>
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

        <PhotoForensics />

        <ErrorsByUser />
      </div>
    </main>
  );
}
