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

/** A board polls every ~30 s and the server stamps last_used_at at most every
 *  2 min, so 10 min of silence means it's unplugged or off Wi-Fi. */
const OFFLINE_AFTER_MS = 10 * 60 * 1000;

function isOnline(k: { last_used_at: string | null; revoked_at: string | null }, now: number) {
  return !k.revoked_at && !!k.last_used_at && now - new Date(k.last_used_at).getTime() < OFFLINE_AFTER_MS;
}

type DisplayMessage = {
  id: string;
  to_username: string | null;
  from_username: string | null;
  body: string;
  created_at: string;
  expires_at: string;
};

const MESSAGE_MAX = 48;
const EMOJI = ["🔥", "❤️", "👏", "🏃"];

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

  const [messages, setMessages] = useState<DisplayMessage[] | null>(null);
  const [msgTo, setMsgTo] = useState("");
  const [msgText, setMsgText] = useState("");
  const [msgBusy, setMsgBusy] = useState(false);
  const [msgNote, setMsgNote] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [res, msgs] = await Promise.all([
      getData<{ keys: DisplayKey[] }>("display-keys"),
      getData<{ messages: DisplayMessage[] }>("display-messages"),
    ]);
    setKeys(res.keys);
    setMessages(msgs.messages);
  }, []);

  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    load().catch((e) => setError(String(e?.message ?? e)));
    // Keep the online/offline status current while the tab is open.
    const t = setInterval(() => {
      setNow(Date.now());
      load().catch(() => {});
    }, 60_000);
    return () => clearInterval(t);
  }, [load]);

  const offline = (keys ?? []).filter((k) => !k.revoked_at && !isOnline(k, now));
  // People with a live desk display (one entry each).
  const recipients = Array.from(
    new Set((keys ?? []).filter((k) => !k.revoked_at && k.username).map((k) => k.username as string)),
  );

  async function sendMessage() {
    setError(null);
    setMsgNote(null);
    setMsgBusy(true);
    try {
      const res = await postData<{ message: DisplayMessage }>("display-messages", {
        username: msgTo || recipients[0],
        text: msgText,
      });
      setMsgNote(`Sent to ${res.message.to_username}'s desk: "${res.message.body}"`);
      setMsgText("");
      await load();
    } catch (e: any) {
      setError(String(e?.message ?? e));
    } finally {
      setMsgBusy(false);
    }
  }

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
      <a
        href="/admin/desk"
        className="flex items-center justify-between rounded-xl border border-white/10 bg-white/[0.04] p-4 text-sm font-bold"
      >
        <span>📱 My Desk remote — styles, scenes, messages and live data for your own board</span>
        <span style={{ color: MAD_RED }}>Open →</span>
      </a>
      {offline.length > 0 && (
        <div className="rounded-xl border border-red-400/30 bg-red-400/10 p-4 text-sm text-red-200">
          {offline.length === 1 ? "1 display is" : `${offline.length} displays are`} offline:{" "}
          {offline.map((k) => k.label || k.username).join(", ")}. Not heard from in 10+ minutes
          (unplugged, or lost Wi-Fi).
        </div>
      )}
      <section className={`${CARD} p-5`}>
        <h2 className="text-lg font-bold">Send to a desk</h2>
        <p className="mt-1 text-sm text-white/50">
          Scrolls across their display with a little mascot wave. Letters, numbers and
          🔥 ❤️ 👏 🏃 only; it disappears after 24 hours.
        </p>
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <select
            value={msgTo || recipients[0] || ""}
            onChange={(e) => setMsgTo(e.target.value)}
            className="rounded-xl border border-white/10 bg-black/40 px-3 py-2 text-sm outline-none"
          >
            {recipients.length === 0 && <option value="">No displays yet</option>}
            {recipients.map((u) => (
              <option key={u} value={u}>
                {u}&apos;s desk
              </option>
            ))}
          </select>
          <input
            value={msgText}
            maxLength={MESSAGE_MAX}
            onChange={(e) => setMsgText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && msgText.trim() && recipients.length && !msgBusy) sendMessage();
            }}
            placeholder="NICE MILE 🔥"
            className="min-w-[14rem] flex-1 rounded-xl border border-white/10 bg-black/40 px-3 py-2 text-sm uppercase outline-none focus:border-white/30"
          />
          {EMOJI.map((e) => (
            <button
              key={e}
              onClick={() => setMsgText((t) => (t + " " + e).slice(0, MESSAGE_MAX))}
              className="rounded-lg border border-white/10 px-2 py-1.5 text-sm"
              title="Add to message"
            >
              {e}
            </button>
          ))}
          <button
            onClick={sendMessage}
            disabled={msgBusy || !msgText.trim() || recipients.length === 0}
            className="rounded-xl px-4 py-2 text-sm font-semibold disabled:opacity-40"
            style={{ background: MAD_RED }}
          >
            Send
          </button>
        </div>
        <p className="mt-2 text-xs text-white/40">{msgText.length}/{MESSAGE_MAX}</p>
        {msgNote && <p className="mt-2 text-sm text-emerald-300">{msgNote}</p>}
        {messages && messages.length > 0 && (
          <ul className="mt-4 space-y-1.5 text-sm">
            {messages.slice(0, 8).map((m) => {
              const live = new Date(m.expires_at).getTime() > now;
              return (
                <li key={m.id} className={`flex flex-wrap gap-x-3 ${live ? "" : "opacity-40"}`}>
                  <span className="text-white/50">{fmtDateTime(m.created_at)}</span>
                  <span>
                    {m.from_username ?? "admin"} → {m.to_username}
                  </span>
                  <span className="font-mono">{m.body}</span>
                  {!live && <span className="text-xs">expired</span>}
                </li>
              );
            })}
          </ul>
        )}
      </section>

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
                <th className="font-medium">Status</th>
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
                  <td>
                    {k.revoked_at ? null : isOnline(k, now) ? (
                      <span className="inline-flex items-center gap-1.5 text-xs text-emerald-300">
                        <span className="h-2 w-2 rounded-full bg-emerald-400" /> Online
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5 text-xs text-red-300">
                        <span className="h-2 w-2 rounded-full bg-red-400" /> Offline
                      </span>
                    )}
                  </td>
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
