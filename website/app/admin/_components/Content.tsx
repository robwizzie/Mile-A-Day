"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Card,
  Chip,
  fmt,
  fmtBytes,
  fmtDateTime,
  getData,
  Loading,
  mediaSrc,
  postData,
  SegmentedControl,
  StatCard,
} from "./lib";
import { TimeSeriesBars } from "./charts";

// ─── Types ──────────────────────────────────────────────────────────

type Storage = {
  disk: { total: number; free: number; used: number; used_pct: number } | null;
  uploads: { total_bytes: number; file_count: number };
  posts_media: {
    total_bytes: number;
    file_count: number;
    avg_bytes: number;
    largest: { file: string; bytes: number }[];
  };
  profile_media: { total_bytes: number; file_count: number };
  integrity: {
    referenced_on_disk: number;
    orphan_files: number;
    orphan_bytes: number;
    missing_files: number;
  };
  generated_at: string;
};

type PostsSummary = {
  total: number;
  live: number;
  deleted: number;
  feed: number;
  story: number;
  auto_cards: number;
  user_photos: number;
  today: number;
  posters: number;
};

type PostsDay = { date: string; count: number; user_count: number };

type PostRow = {
  post_id: string;
  user_id: string;
  username: string | null;
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
  media_file_exists: boolean | null;
};

type PostsListResponse = { total: number; posts: PostRow[] };
type PostFilter =
  | "all"
  | "live"
  | "deleted"
  | "feed"
  | "story"
  | "auto"
  | "user";

// ─── Storage ────────────────────────────────────────────────────────

function StoragePanel() {
  const [s, setS] = useState<Storage | null>(null);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(() => {
    getData<Storage>("storage")
      .then(setS)
      .catch((e) => {
        if (e?.message !== "unauthorized") setErr("Failed to load storage.");
      });
  }, []);
  useEffect(() => load(), [load]);

  if (err) return <Card title="Storage">{err}</Card>;
  if (!s)
    return (
      <Card title="Storage">
        <Loading />
      </Card>
    );

  return (
    <Card
      title="Storage"
      hint="Media lives on the app server's local disk (uploads/)."
      actions={
        <button
          onClick={load}
          className="rounded-md border border-white/10 px-2 py-1 text-xs text-white/60 hover:text-white"
        >
          Refresh
        </button>
      }
    >
      {/* Disk usage bar */}
      {s.disk ? (
        <div className="mb-5">
          <div className="mb-1.5 flex items-baseline justify-between text-sm">
            <span className="text-white/70">
              Disk — {fmtBytes(s.disk.used)} used of {fmtBytes(s.disk.total)}
            </span>
            <span className="text-white/50">
              {fmtBytes(s.disk.free)} free · {s.disk.used_pct}%
            </span>
          </div>
          <div className="flex h-3 overflow-hidden rounded-full bg-white/[0.06]">
            <div
              className="h-full bg-[#c72554]"
              style={{ width: `${Math.min(s.disk.used_pct, 100)}%` }}
              title={`Used ${fmtBytes(s.disk.used)}`}
            />
          </div>
          <div className="mt-1.5 flex items-center gap-3 text-[11px] text-white/40">
            <span>
              <span className="mr-1 inline-block h-2 w-2 rounded-sm bg-[#c72554]" />
              uploads {fmtBytes(s.uploads.total_bytes)} (
              {(
                (s.uploads.total_bytes / Math.max(s.disk.used, 1)) *
                100
              ).toFixed(1)}
              % of used)
            </span>
          </div>
        </div>
      ) : (
        <p className="mb-4 text-xs text-white/40">
          Disk capacity unavailable in this environment.
        </p>
      )}

      {/* Media breakdown */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatCard
          label="Post photos"
          value={fmtBytes(s.posts_media.total_bytes)}
          sub={`${fmt(s.posts_media.file_count)} files`}
        />
        <StatCard
          label="Profile images"
          value={fmtBytes(s.profile_media.total_bytes)}
          sub={`${fmt(s.profile_media.file_count)} files`}
        />
        <StatCard
          label="Avg photo"
          value={fmtBytes(s.posts_media.avg_bytes)}
          sub="per post"
        />
        <StatCard
          label="Uploads total"
          value={fmtBytes(s.uploads.total_bytes)}
          sub={`${fmt(s.uploads.file_count)} files`}
        />
      </div>

      {/* Integrity */}
      <div className="mt-4 grid gap-3 sm:grid-cols-3">
        <div className="rounded-lg border border-white/10 bg-white/[0.02] p-3">
          <div className="text-xs text-white/40">Referenced on disk</div>
          <div className="mt-0.5 text-xl font-semibold text-white">
            {fmt(s.integrity.referenced_on_disk)}
          </div>
          <div className="text-xs text-white/40">files backing a post</div>
        </div>
        <div
          className={`rounded-lg border p-3 ${
            s.integrity.orphan_files > 0
              ? "border-amber-400/30 bg-amber-400/[0.06]"
              : "border-white/10 bg-white/[0.02]"
          }`}
        >
          <div className="text-xs text-white/40">Orphaned files</div>
          <div className="mt-0.5 text-xl font-semibold text-white">
            {fmt(s.integrity.orphan_files)}
          </div>
          <div className="text-xs text-white/40">
            {fmtBytes(s.integrity.orphan_bytes)} reclaimable
          </div>
        </div>
        <div
          className={`rounded-lg border p-3 ${
            s.integrity.missing_files > 0
              ? "border-[#c72554]/40 bg-[#c72554]/[0.08]"
              : "border-white/10 bg-white/[0.02]"
          }`}
        >
          <div className="text-xs text-white/40">Missing files</div>
          <div className="mt-0.5 text-xl font-semibold text-white">
            {fmt(s.integrity.missing_files)}
          </div>
          <div className="text-xs text-white/40">live posts, file gone</div>
        </div>
      </div>
    </Card>
  );
}

// ─── Post stats + trend ─────────────────────────────────────────────

function PostStats() {
  const [summary, setSummary] = useState<PostsSummary | null>(null);
  const [byDay, setByDay] = useState<PostsDay[]>([]);

  useEffect(() => {
    Promise.all([
      getData<PostsSummary>("posts/summary"),
      getData<PostsDay[]>("posts/by-day"),
    ])
      .then(([s, d]) => {
        setSummary(s);
        setByDay(d);
      })
      .catch(() => {
        /* unauthorized handled in getData */
      });
  }, []);

  if (!summary) return <Loading />;

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard
          label="Total posts"
          value={fmt(summary.total)}
          sub={`${summary.today} today`}
          accent
        />
        <StatCard
          label="Live"
          value={fmt(summary.live)}
          sub={`${summary.deleted} deleted`}
        />
        <StatCard
          label="User photos"
          value={fmt(summary.user_photos)}
          sub={`${summary.auto_cards} auto cards`}
        />
        <StatCard
          label="Posters"
          value={fmt(summary.posters)}
          sub={`${summary.feed} feed · ${summary.story} story`}
        />
      </div>
      <Card>
        <TimeSeriesBars
          data={byDay.map((d) => ({ date: d.date, value: d.count }))}
          label="Posts per day — last 30 days"
          color="#a78bfa"
          hoverColor="#c4b5fd"
          formatValue={(v) => v.toFixed(0)}
        />
      </Card>
    </div>
  );
}

// ─── All-posts browser (supersedes the old forensics list) ──────────

const FILTERS: { value: PostFilter; label: string }[] = [
  { value: "all", label: "All" },
  { value: "live", label: "Live" },
  { value: "user", label: "Photos" },
  { value: "auto", label: "Auto" },
  { value: "feed", label: "Feed" },
  { value: "story", label: "Story" },
  { value: "deleted", label: "Deleted" },
];
const PAGE_SIZE = 24;

function PostsBrowser() {
  const [filter, setFilter] = useState<PostFilter>("all");
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [offset, setOffset] = useState(0);
  const [data, setData] = useState<PostsListResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);

  useEffect(() => {
    const t = setTimeout(() => {
      setQuery(search.trim());
      setOffset(0);
    }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams({
        filter,
        limit: String(PAGE_SIZE),
        offset: String(offset),
      });
      if (query) params.set("search", query);
      setData(await getData<PostsListResponse>(`posts?${params.toString()}`));
    } catch {
      /* unauthorized handled in getData */
    } finally {
      setLoading(false);
    }
  }, [filter, query, offset]);

  useEffect(() => {
    load();
  }, [load]);

  async function restore(id: string) {
    setBusyId(id);
    try {
      await postData(`posts/${id}/restore`);
      await load();
    } catch {
      /* surfaced via reload; ignore */
    } finally {
      setBusyId(null);
    }
  }

  const total = data?.total ?? 0;

  return (
    <Card
      title="All posts"
      hint="Every post, newest first. Filter by lifecycle, surface, or origin; restore soft-deleted posts whose file still exists."
      actions={
        <span className="text-xs text-white/40">
          {loading ? "Loading…" : `${fmt(total)} match`}
        </span>
      }
    >
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SegmentedControl<PostFilter>
          value={filter}
          onChange={(v) => {
            setFilter(v);
            setOffset(0);
          }}
          options={FILTERS}
        />
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search caption or @user…"
          className="w-full max-w-[240px] rounded-lg border border-white/10 bg-black/40 px-3 py-1.5 text-sm text-white placeholder:text-white/30 focus:border-[#c72554]/60 focus:outline-none"
        />
      </div>

      {!data ? (
        <Loading />
      ) : data.posts.length === 0 ? (
        <p className="text-sm text-white/40">No posts match.</p>
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6">
          {data.posts.map((p) => (
            <div
              key={p.post_id}
              className="group relative overflow-hidden rounded-lg border border-white/10 bg-black/40"
            >
              <div className="relative aspect-[3/4]">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={mediaSrc(p.media_url)}
                  alt=""
                  className={`h-full w-full object-cover ${
                    p.deleted_at ? "opacity-40" : ""
                  }`}
                  loading="lazy"
                  onError={(e) => {
                    (e.target as HTMLImageElement).style.opacity = "0.12";
                  }}
                />
                <div className="absolute left-1 top-1 flex flex-wrap gap-1">
                  {p.deleted_at && <Chip text="DELETED" tone="bad" />}
                  {p.media_file_exists === false && (
                    <Chip text="FILE GONE" tone="bad" />
                  )}
                </div>
                <div className="absolute bottom-1 left-1 flex flex-wrap gap-1">
                  {p.is_auto && <Chip text="AUTO" tone="muted" />}
                  {p.share_to_story && <Chip text="STORY" tone="muted" />}
                </div>
              </div>
              <div className="p-2">
                <div className="truncate text-xs text-white/80">
                  {p.username ? `@${p.username}` : p.user_id.slice(0, 8)}
                </div>
                <div className="truncate text-[11px] text-white/40">
                  {p.local_date}
                  {p.workout_distance != null
                    ? ` · ${p.workout_distance.toFixed(2)} mi`
                    : ""}
                </div>
                {p.deleted_at && p.media_file_exists !== false && (
                  <button
                    onClick={() => restore(p.post_id)}
                    disabled={busyId === p.post_id}
                    className="mt-1.5 w-full rounded border border-emerald-400/40 py-1 text-[11px] font-medium text-emerald-300 disabled:opacity-40"
                  >
                    {busyId === p.post_id ? "…" : "Restore"}
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {total > PAGE_SIZE && (
        <div className="mt-4 flex items-center justify-between">
          <button
            onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}
            disabled={offset === 0 || loading}
            className="rounded-md border border-white/10 px-3 py-1.5 text-sm text-white/60 hover:text-white disabled:opacity-30"
          >
            ← Prev
          </button>
          <span className="text-xs text-white/40">
            Page {Math.floor(offset / PAGE_SIZE) + 1} of{" "}
            {Math.max(1, Math.ceil(total / PAGE_SIZE))}
          </span>
          <button
            onClick={() => setOffset(offset + PAGE_SIZE)}
            disabled={offset + PAGE_SIZE >= total || loading}
            className="rounded-md border border-white/10 px-3 py-1.5 text-sm text-white/60 hover:text-white disabled:opacity-30"
          >
            Next →
          </button>
        </div>
      )}
    </Card>
  );
}

// ─── Targeted per-user forensics (support tool) ─────────────────────

type ForensicsPost = {
  post_id: string;
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
    <Card
      title="Photo forensics"
      hint="“My photo disappeared” investigator — every post for one user in a date window, including soft-deleted rows, with the media file's fate on disk and the exact filename for recovery."
    >
      <div className="mb-4 flex flex-wrap items-end gap-3">
        <label className="text-xs text-white/50">
          User id (or “me”)
          <input
            value={userId}
            onChange={(e) => setUserId(e.target.value)}
            className="mt-1 block w-44 rounded-md border border-white/10 bg-black/40 px-2 py-1.5 text-sm text-white"
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
                      text={`DELETED ${fmtDateTime(p.deleted_at)}`}
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
    </Card>
  );
}

export function ContentTab() {
  return (
    <div className="space-y-6">
      <StoragePanel />
      <PostStats />
      <PostsBrowser />
      <PhotoForensics />
    </div>
  );
}
