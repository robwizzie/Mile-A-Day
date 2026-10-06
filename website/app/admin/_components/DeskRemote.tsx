"use client";

import { useCallback, useEffect, useState } from "react";
import { getData, postData } from "./lib";
import { MAD_RED, MAD_SUCCESS } from "./theme";

/**
 * The desk remote (/admin/desk): your OWN LED desk counter from your phone.
 * Pick the style and mascot, play any scene on the board, message another
 * desk and read what was sent to yours, and watch the live data the board
 * is showing. Everything goes through GET/POST /admin/desk*, which only ever
 * touch the signed-in admin's own desk. The board picks changes up on its
 * next poll (about 15 s).
 */

type Feed = {
  community: Record<string, number>;
  me: {
    username: string | null;
    mile_done: boolean;
    miles_today: number;
    streak: number;
    running_now: boolean;
    live_miles: number | null;
  };
  friends_running: { name: string; miles: number }[];
  friends_finished: { id: string; name: string; miles: number }[];
  friends_at_risk: { count: number; top: { name: string; streak: number }[] };
};

type Remote = {
  username: string | null;
  styles: string[];
  mascots: string[];
  plays: string[];
  settings: { style: number | null; mascot: number | null; rev: number };
  boards: { label: string; last_seen: string | null; online: boolean }[];
  messages: { id: string; direction: "in" | "out"; who: string; text: string; at: string }[];
  recipients: string[];
  live: Feed;
};

const STYLE_INFO: Record<string, string> = {
  CLASSIC: "Users, today, total and your streak",
  SPOTLIGHT: "One stat at a time, big",
  ARCADE: "Your mascot runs and grabs coins",
  BIG: "Giant numbers",
  CAMPFIRE: "Cozy fire with your mascot",
  RACE: "Today vs yesterday, racing",
  CLOCK: "Clock and your streak",
};

const PLAY_LABEL: Record<string, string> = {
  nudge: "Nudge", hype: "Hype", friend: "Friend running", finished: "Friend finished",
  atrisk: "Streaks at risk", mile: "Mile done", streak: "Streak milestone",
  milestone: "Community milestone", user: "New user", pr: "Personal record",
  morning: "Good morning", yearago: "1 year ago", recap: "9pm recap", newyear: "New Year",
  medal: "New medal", review: "App Store review", comment: "New comment",
  message: "Desk message", holiday: "Holiday",
};

const MESSAGE_MAX = 48;
const EMOJI = ["🔥", "❤️", "👏", "🏃"];
const TOKENS: Record<string, string> = { "[FIRE]": "🔥", "[HEART]": "❤️", "[CLAP]": "👏", "[RUN]": "🏃" };

function pretty(text: string) {
  return text.replace(/\[(FIRE|HEART|CLAP|RUN)\]/g, (t) => TOKENS[t] ?? t);
}

function ago(iso: string | null): string {
  if (!iso) return "never";
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  return `${Math.floor(s / 86400)} d ago`;
}

function Section({ title, children, right }: { title: string; children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <section className="rounded-2xl border border-white/10 bg-white/[0.04] p-4">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-sm font-extrabold uppercase tracking-wider text-white/60">{title}</h2>
        {right}
      </div>
      {children}
    </section>
  );
}

export function DeskRemote() {
  const [data, setData] = useState<Remote | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [mascot, setMascot] = useState<number>(1);
  const [to, setTo] = useState("");
  const [text, setText] = useState("");

  const load = useCallback(async () => {
    try {
      const d = await getData<Remote>("desk");
      setData(d);
      setError(null);
      if (d.settings.mascot != null) setMascot(d.settings.mascot);
      setTo((cur) => cur || d.recipients[0] || "");
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);

  useEffect(() => {
    load();
    const id = setInterval(load, 15000);      // live data refreshes like the board
    return () => clearInterval(id);
  }, [load]);

  const say = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(null), 3000);
  };

  async function choose(body: { style?: number; mascot?: number }) {
    setBusy(true);
    try {
      const r = await postData<{ settings: Remote["settings"] }>("desk/settings", body);
      setData((d) => (d ? { ...d, settings: r.settings } : d));
      if (r.settings.mascot != null) setMascot(r.settings.mascot);
      say("Sent — your desk switches in about 15 seconds");
    } catch (e) {
      say((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function play(kind: string) {
    try {
      await postData("desk/play", { kind });
      say(`${PLAY_LABEL[kind] ?? "Playing"} — on your desk in about 15 seconds`);
    } catch (e) {
      say((e as Error).message);
    }
  }

  async function send() {
    if (!to || !text.trim()) return;
    setBusy(true);
    try {
      await postData("display-messages", { username: to, text });
      setText("");
      say(`Sent to ${to}'s desk`);
      load();
    } catch (e) {
      say((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  if (error && !data) {
    return <main className="min-h-screen bg-black p-6 text-white/70">Couldn't load your desk: {error}</main>;
  }
  if (!data) {
    return <main className="min-h-screen bg-black p-6 text-white/40">Loading your desk…</main>;
  }

  const live = data.live;
  const style = data.settings.style;
  const online = data.boards.some((b) => b.online);
  const lastSeen = data.boards.map((b) => b.last_seen).filter(Boolean).sort().pop() ?? null;
  const scenes = data.plays.filter((p) => p !== "demo" && p !== "show");

  return (
    <main
      className="min-h-screen bg-black pb-24 text-white"
      style={{ fontFamily: "ui-rounded, var(--font-nunito), system-ui, sans-serif",
               paddingTop: "max(env(safe-area-inset-top), 16px)" }}
    >
      <div className="mx-auto flex max-w-md flex-col gap-4 px-4">
        {/* ── header ── */}
        <header className="flex items-center justify-between pt-2">
          <div>
            <h1 className="text-2xl font-extrabold">My Desk</h1>
            <p className="text-sm text-white/50">@{data.username}</p>
          </div>
          <div className="flex items-center gap-2 rounded-full bg-white/[0.06] px-3 py-1.5 text-xs font-bold">
            <span className="h-2 w-2 rounded-full" style={{ background: online ? MAD_SUCCESS : "#666" }} />
            {data.boards.length === 0 ? "No board yet" : online ? "Online" : `Offline · ${ago(lastSeen)}`}
          </div>
        </header>

        {/* ── now showing + mascot ── */}
        <Section title="On your desk">
          <div className="overflow-hidden rounded-xl bg-[#111]">
            {style != null ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={`/desk/style${style}_m${mascot}.gif`} alt={data.styles[style]} className="w-full [image-rendering:pixelated]" />
            ) : (
              <p className="p-6 text-center text-sm text-white/50">
                Your desk is showing whatever its buttons picked. Choose a style below to set it from here.
              </p>
            )}
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2">
            {data.mascots.map((m, i) => (
              <button
                key={m}
                disabled={busy}
                onClick={() => choose({ mascot: i })}
                className="rounded-xl py-2.5 text-sm font-extrabold transition"
                style={{ background: mascot === i ? MAD_RED : "rgba(255,255,255,0.06)" }}
              >
                {m === "FLAMEY" ? "🔥 Flamey" : "🏃 Runner"}
              </button>
            ))}
          </div>
        </Section>

        {/* ── styles ── */}
        <Section title="Styles">
          <div className="grid grid-cols-2 gap-3">
            {data.styles.map((s, i) => (
              <button
                key={s}
                disabled={busy}
                onClick={() => choose({ style: i, mascot })}
                className="overflow-hidden rounded-xl border text-left transition"
                style={{ borderColor: style === i ? MAD_RED : "rgba(255,255,255,0.08)",
                         boxShadow: style === i ? `0 0 0 1px ${MAD_RED}` : undefined }}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={`/desk/style${i}_m${mascot}.gif`} alt="" loading="lazy" className="w-full [image-rendering:pixelated]" />
                <div className="px-2.5 py-2">
                  <div className="text-xs font-extrabold">{s.charAt(0) + s.slice(1).toLowerCase()}</div>
                  <div className="text-[11px] leading-tight text-white/50">{STYLE_INFO[s]}</div>
                </div>
              </button>
            ))}
          </div>
          <p className="mt-3 text-xs text-white/40">Race and Clock need your display key (they use your own data).</p>
        </Section>

        {/* ── messages ── */}
        <Section title="Messages">
          {data.recipients.length > 0 ? (
            <div className="flex flex-col gap-2">
              <div className="flex gap-2">
                <select
                  value={to}
                  onChange={(e) => setTo(e.target.value)}
                  className="rounded-xl bg-white/[0.06] px-3 py-2.5 text-sm font-bold"
                >
                  {data.recipients.map((r) => <option key={r} value={r}>@{r}</option>)}
                </select>
                <input
                  value={text}
                  maxLength={MESSAGE_MAX}
                  onChange={(e) => setText(e.target.value)}
                  placeholder="Nice mile!"
                  className="min-w-0 flex-1 rounded-xl bg-white/[0.06] px-3 py-2.5 text-base outline-none"
                />
              </div>
              <div className="flex items-center gap-2">
                {EMOJI.map((e) => (
                  <button key={e} onClick={() => setText((t) => (t + " " + e).trim().slice(0, MESSAGE_MAX))}
                          className="rounded-xl bg-white/[0.06] px-3 py-2 text-lg">{e}</button>
                ))}
                <button
                  disabled={busy || !text.trim()}
                  onClick={send}
                  className="ml-auto rounded-xl px-5 py-2.5 text-sm font-extrabold disabled:opacity-40"
                  style={{ background: MAD_RED }}
                >
                  Send
                </button>
              </div>
              <p className="text-[11px] text-white/40">Letters, numbers and 🔥 ❤️ 👏 🏃 only · {MESSAGE_MAX - text.length} left</p>
            </div>
          ) : (
            <p className="text-sm text-white/50">Nobody else has a desk yet.</p>
          )}
          <ul className="mt-4 flex flex-col gap-2">
            {data.messages.length === 0 && <li className="text-sm text-white/40">No messages in the last 2 weeks.</li>}
            {data.messages.map((m) => (
              <li key={m.id + m.at}
                  className={`max-w-[85%] rounded-2xl px-3 py-2 ${m.direction === "out" ? "self-end" : "self-start bg-white/[0.08]"}`}
                  style={m.direction === "out" ? { background: MAD_RED } : undefined}>
                <div className="text-[11px] font-bold opacity-70">
                  {m.direction === "out" ? `To @${m.who}` : `From @${m.who}`} · {ago(m.at)}
                </div>
                <div className="text-sm font-semibold">{pretty(m.text)}</div>
              </li>
            ))}
          </ul>
        </Section>

        {/* ── live ── */}
        <Section title="Live now" right={<span className="text-[11px] text-white/40">updates every 15 s</span>}>
          <div className="grid grid-cols-3 gap-2 text-center">
            <Stat label="My mile" value={live.me.mile_done ? "Done ✓" : live.me.running_now ? `${(live.me.live_miles ?? 0).toFixed(2)} mi` : "Not yet"}
                  color={live.me.mile_done ? MAD_SUCCESS : undefined} />
            <Stat label="Streak" value={`🔥 ${live.me.streak}`} />
            <Stat label="Out now" value={String(live.community.out_running_now ?? 0)} />
            <Stat label="Miles today" value={(live.community.miles_today ?? 0).toLocaleString()} />
            <Stat label="Users" value={(live.community.total_users ?? 0).toLocaleString()} />
            <Stat label="Hypes today" value={(live.community.hypes_today ?? 0).toLocaleString()} />
          </div>
          <List title="Friends running" empty="No friends out right now"
                rows={live.friends_running.map((f) => [`@${f.name}`, `${f.miles.toFixed(2)} mi`])}
                onPlay={live.friends_running.length ? () => play("friend") : undefined} />
          <List title="Just finished" empty="Nobody in the last 30 min"
                rows={live.friends_finished.map((f) => [`@${f.name}`, `${f.miles.toFixed(2)} mi`])} />
          <List title={`Streaks at risk (${live.friends_at_risk.count})`} empty="Everyone's safe today"
                rows={live.friends_at_risk.top.map((f) => [`@${f.name}`, `🔥 ${f.streak}`])}
                onPlay={live.friends_at_risk.count ? () => play("atrisk") : undefined} />
        </Section>

        {/* ── play on my desk ── */}
        <Section title="Play on my desk">
          <div className="mb-3 grid grid-cols-2 gap-2">
            <button onClick={() => play("demo")} className="rounded-xl py-2.5 text-sm font-extrabold" style={{ background: MAD_RED }}>
              ▶ Play everything
            </button>
            <button onClick={() => play("show")} className="rounded-xl bg-white/[0.08] py-2.5 text-sm font-extrabold">
              ▶ Stat show
            </button>
          </div>
          <div className="grid grid-cols-2 gap-3">
            {scenes.map((k) => (
              <button key={k} onClick={() => play(k)} className="overflow-hidden rounded-xl border border-white/[0.08] text-left">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={`/desk/play_${k}_m${mascot}.gif`} alt="" loading="lazy" className="w-full [image-rendering:pixelated]" />
                <div className="px-2.5 py-2 text-xs font-extrabold">▶ {PLAY_LABEL[k] ?? k}</div>
              </button>
            ))}
          </div>
        </Section>

        <p className="pb-6 text-center text-[11px] text-white/30">
          Tip: in Safari tap Share → Add to Home Screen to open this like an app.
        </p>
      </div>

      {toast && (
        <div className="fixed inset-x-0 bottom-6 z-50 mx-auto w-fit max-w-[90%] rounded-full bg-white px-4 py-2.5 text-sm font-bold text-black shadow-lg"
             style={{ marginBottom: "env(safe-area-inset-bottom)" }}>
          {toast}
        </div>
      )}
    </main>
  );
}

function Stat({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="rounded-xl bg-white/[0.05] px-2 py-2.5">
      <div className="truncate text-base font-extrabold" style={color ? { color } : undefined}>{value}</div>
      <div className="text-[10px] font-bold uppercase tracking-wider text-white/40">{label}</div>
    </div>
  );
}

function List({ title, rows, empty, onPlay }: { title: string; rows: string[][]; empty: string; onPlay?: () => void }) {
  return (
    <div className="mt-4">
      <div className="mb-1.5 flex items-center justify-between">
        <h3 className="text-xs font-extrabold text-white/70">{title}</h3>
        {onPlay && (
          <button onClick={onPlay} className="text-[11px] font-bold" style={{ color: MAD_RED }}>Show on desk ▶</button>
        )}
      </div>
      {rows.length === 0 ? (
        <p className="text-xs text-white/35">{empty}</p>
      ) : (
        <ul className="divide-y divide-white/[0.06]">
          {rows.map(([a, b]) => (
            <li key={a} className="flex justify-between py-1.5 text-sm">
              <span className="truncate font-semibold">{a}</span>
              <span className="text-white/60">{b}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
