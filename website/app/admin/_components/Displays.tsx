"use client";

import { useCallback, useEffect, useState } from "react";
import { fmtDateTime, getData, Loading, postData } from "./lib";
import { CARD, MAD_RED } from "./theme";

/**
 * Desk displays (the LED "Mile A Day counter"). Each key lets ONE device read
 * GET /display/feed as ONE user — community totals plus that person's own
 * mile, streak and nudges/hypes. The key is shown once, here, right after it
 * is created; the backend keeps only its hash. Revoke a key and that display
 * stops on its next poll.
 */

type DisplayKey = {
  id: string;
  username: string | null;
  label: string;
  key_prefix: string;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
};

export function DisplaysTab() {
  const [keys, setKeys] = useState<DisplayKey[] | null>(null);
  const [username, setUsername] = useState("");
  const [label, setLabel] = useState("");
  const [fresh, setFresh] = useState<{ key: string; who: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);

  const load = useCallback(async () => {
    const res = await getData<{ keys: DisplayKey[] }>("display-keys");
    setKeys(res.keys);
  }, []);

  useEffect(() => {
    load().catch((e) => setError(String(e?.message ?? e)));
  }, [load]);

  // The plaintext key is shown once; drop it from the page after 2 minutes.
  useEffect(() => {
    if (!fresh) return;
    const t = setTimeout(() => setFresh(null), 120_000);
    return () => clearTimeout(t);
  }, [fresh]);

  async function create() {
    setError(null);
    setBusy(true);
    try {
      const qs = new URLSearchParams({ username: username.trim(), label: label.trim() });
      const res = await postData<{ key: string }>(`display-keys?${qs}`);
      setFresh({ key: res.key, who: username.trim() });
      setCopied(false);
      setUsername("");
      setLabel("");
      await load();
    } catch (e: any) {
      setError(String(e?.message ?? e));
    } finally {
      setBusy(false);
    }
  }

  async function revoke(k: DisplayKey) {
    if (!confirm(`Revoke ${k.label || "this display"} (${k.username})? It stops on its next poll.`)) return;
    setError(null);
    try {
      await postData(`display-keys/${k.id}/revoke`);
      await load();
    } catch (e: any) {
      setError(String(e?.message ?? e));
    }
  }

  return (
    <div className="space-y-6">
      <section className={`${CARD} p-5`}>
        <h2 className="text-lg font-bold">New desk display key</h2>
        <p className="mt-1 text-sm text-white/50">
          The display shows community totals plus this person&apos;s own mile, streak and the
          nudges/hypes sent to them. Nothing else.
        </p>
        <div className="mt-4 flex flex-wrap gap-2">
          <input
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="username"
            className="rounded-xl border border-white/10 bg-black/40 px-3 py-2 text-sm outline-none focus:border-white/30"
          />
          <input
            value={label}
            onChange={(e) => setLabel(e.target.value)}
            placeholder="label (e.g. Rob's desk)"
            className="min-w-[14rem] flex-1 rounded-xl border border-white/10 bg-black/40 px-3 py-2 text-sm outline-none focus:border-white/30"
          />
          <button
            onClick={create}
            disabled={busy || !username.trim()}
            className="rounded-xl px-4 py-2 text-sm font-semibold disabled:opacity-40"
            style={{ background: MAD_RED }}
          >
            Create key
          </button>
        </div>
        {fresh && (
          <div className="mt-4 rounded-xl border border-amber-400/30 bg-amber-400/10 p-4">
            <p className="text-sm font-semibold text-amber-200">
              Key for {fresh.who}. Copy it now: it will not be shown again (hides in 2 minutes).
            </p>
            <code className="mt-2 block break-all rounded-lg bg-black/50 p-2 text-xs">{fresh.key}</code>
            <p className="mt-2 text-xs text-white/50">
              Put it in the display&apos;s settings.toml as MAD_DISPLAY_KEY = &quot;…&quot;.
            </p>
            <div className="mt-3 flex gap-2">
              <button
                onClick={async () => {
                  await navigator.clipboard.writeText(fresh.key);
                  setCopied(true);
                }}
                className="rounded-lg border border-white/15 px-3 py-1.5 text-xs"
              >
                {copied ? "Copied" : "Copy"}
              </button>
              <button
                onClick={() => setFresh(null)}
                className="rounded-lg border border-white/15 px-3 py-1.5 text-xs text-white/60"
              >
                Done, hide it
              </button>
            </div>
          </div>
        )}
        {error && <p className="mt-3 text-sm text-red-400">{error}</p>}
      </section>

      <section className={`${CARD} p-5`}>
        <h2 className="text-lg font-bold">Display keys</h2>
        {!keys ? (
          <Loading />
        ) : keys.length === 0 ? (
          <p className="mt-2 text-sm text-white/50">No display keys yet.</p>
        ) : (
          <table className="mt-3 w-full text-sm">
            <thead className="text-left text-white/40">
              <tr>
                <th className="py-1.5 font-medium">Label</th>
                <th className="font-medium">User</th>
                <th className="font-medium">Key</th>
                <th className="font-medium">Last seen</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {keys.map((k) => (
                <tr key={k.id} className={`border-t border-white/[0.06] ${k.revoked_at ? "opacity-40" : ""}`}>
                  <td className="py-2">{k.label}</td>
                  <td>{k.username ?? "—"}</td>
                  <td className="font-mono text-xs">{k.key_prefix}…</td>
                  <td>{k.last_used_at ? fmtDateTime(k.last_used_at) : "never"}</td>
                  <td className="text-right">
                    {k.revoked_at ? (
                      <span className="text-xs">revoked</span>
                    ) : (
                      <button
                        onClick={() => revoke(k)}
                        className="rounded-lg border border-white/15 px-2.5 py-1 text-xs text-white/70 hover:border-red-400/60 hover:text-red-300"
                      >
                        Revoke
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  );
}
