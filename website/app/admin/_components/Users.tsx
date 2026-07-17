"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Chip,
  fmt,
  fmtDate,
  getData,
  Loading,
  relativeDay,
  SegmentedControl,
} from "./lib";
import { UserModal } from "./UserModal";

type UserRow = {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  role: string | null;
  current_streak: number;
  referral_source: string | null;
  created_at: string;
  terms_accepted_at: string | null;
  total_miles: number;
  last_active: string | null;
  post_count: number;
};

type UsersResponse = { total: number; users: UserRow[] };

type Sort = "recent" | "streak" | "miles" | "active";
const PAGE_SIZE = 25;

export function UsersTab() {
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState(""); // debounced
  const [sort, setSort] = useState<Sort>("recent");
  const [offset, setOffset] = useState(0);
  const [data, setData] = useState<UsersResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [openId, setOpenId] = useState<string | null>(null);

  // Debounce the search box so we don't fire a request per keystroke.
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
        limit: String(PAGE_SIZE),
        offset: String(offset),
        sort,
      });
      if (query) params.set("search", query);
      setData(await getData<UsersResponse>(`users?${params.toString()}`));
    } catch {
      /* unauthorized handled in getData */
    } finally {
      setLoading(false);
    }
  }, [query, sort, offset]);

  useEffect(() => {
    load();
  }, [load]);

  const total = data?.total ?? 0;
  const from = total === 0 ? 0 : offset + 1;
  const to = Math.min(offset + PAGE_SIZE, total);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-1 flex-wrap items-center gap-3">
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search username, name, or email…"
            className="w-full max-w-xs rounded-lg border border-white/10 bg-black/40 px-3 py-2 text-sm text-white placeholder:text-white/30 focus:border-[#c72554]/60 focus:outline-none"
          />
          <SegmentedControl<Sort>
            value={sort}
            onChange={(v) => {
              setSort(v);
              setOffset(0);
            }}
            options={[
              { value: "recent", label: "Newest" },
              { value: "streak", label: "Streak" },
              { value: "miles", label: "Miles" },
              { value: "active", label: "Active" },
            ]}
          />
        </div>
        <div className="text-xs text-white/40">
          {loading ? "Loading…" : `${from}–${to} of ${fmt(total)}`}
        </div>
      </div>

      <div className="rounded-xl border border-white/10 bg-white/[0.03]">
        {!data ? (
          <div className="p-5">
            <Loading />
          </div>
        ) : data.users.length === 0 ? (
          <p className="p-5 text-sm text-white/40">No users match.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-white/10 text-left text-xs text-white/40">
                  <th className="p-3 font-medium">User</th>
                  <th className="p-3 font-medium">Streak</th>
                  <th className="p-3 font-medium">Miles</th>
                  <th className="p-3 font-medium">Posts</th>
                  <th className="p-3 font-medium">Last active</th>
                  <th className="p-3 font-medium">Source</th>
                  <th className="p-3 font-medium">Joined</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5">
                {data.users.map((u) => (
                  <tr
                    key={u.user_id}
                    onClick={() => setOpenId(u.user_id)}
                    className="cursor-pointer transition hover:bg-white/[0.03]"
                  >
                    <td className="p-3">
                      <div className="flex items-center gap-2">
                        <span className="text-white/90">
                          {u.username ? `@${u.username}` : "—"}
                        </span>
                        {u.role && u.role !== "user" && (
                          <Chip text={u.role} tone="info" />
                        )}
                      </div>
                      <div className="text-xs text-white/40">
                        {[u.first_name, u.last_name]
                          .filter(Boolean)
                          .join(" ") ||
                          u.email ||
                          u.user_id.slice(0, 8)}
                      </div>
                    </td>
                    <td className="p-3 text-white/70">
                      {u.current_streak > 0 ? `${u.current_streak}🔥` : "—"}
                    </td>
                    <td className="p-3 text-white/70">
                      {fmt(Math.round(u.total_miles))}
                    </td>
                    <td className="p-3 text-white/70">{fmt(u.post_count)}</td>
                    <td className="p-3 whitespace-nowrap text-white/50">
                      {relativeDay(u.last_active)}
                    </td>
                    <td className="p-3 whitespace-nowrap text-white/50">
                      {u.referral_source ?? "—"}
                    </td>
                    <td className="p-3 whitespace-nowrap text-white/50">
                      {fmtDate(u.created_at)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {total > PAGE_SIZE && (
        <div className="flex items-center justify-between">
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
            disabled={to >= total || loading}
            className="rounded-md border border-white/10 px-3 py-1.5 text-sm text-white/60 hover:text-white disabled:opacity-30"
          >
            Next →
          </button>
        </div>
      )}

      {openId && <UserModal userId={openId} onClose={() => setOpenId(null)} />}
    </div>
  );
}
