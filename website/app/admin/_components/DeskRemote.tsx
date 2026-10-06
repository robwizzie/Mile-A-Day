"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getData, postData } from "./lib";
import { MAD_RED, MAD_SUCCESS } from "./theme";

/**
 * The desk remote (/admin/desk), phone-first. Pick a box (Rob's, Dave's…),
 * then: see its REAL screen (the box's own code, running here in MicroPython
 * WebAssembly on the box's real feed, so the numbers, Flamey's closet look and
 * the season are exactly what's on the desk), set its style and mascot, start
 * its stat show, message another box, and read what happened on it.
 *
 * Nothing here can fake an event: nudges, hypes, runs, medals and messages
 * only ever come from real activity. The chosen box is remembered per phone.
 */

type Box = { id: string; label: string; username: string | null; last_seen: string | null; online: boolean };

type Feed = {
  community: Record<string, number>;
  me: {
    username: string | null;
    mile_done: boolean;
    miles_today: number;
    streak: number;
    running_now: boolean;
    live_miles: number | null;
    local_time: string;
  };
  friends_running: { name: string; miles: number }[];
  friends_finished: { id: string; name: string; miles: number }[];
  friends_at_risk: { count: number; top: { name: string; streak: number }[] };
};

type BoxDetail = {
  box: Box;
  styles: string[];
  mascots: string[];
  settings: { style: number | null; mascot: number | null; rev: number };
  messages: { id: string; direction: "in" | "out"; who: string; text: string; at: string }[];
  recipients: Box[];
  activity: { at: string; kind: string; text: string }[];
  live: Feed;
};

const STORE_KEY = "mad-desk-box";
const STYLE_INFO: Record<string, string> = {
  CLASSIC: "Users, today, total and your streak",
  SPOTLIGHT: "One stat at a time, big",
  ARCADE: "Your mascot runs and grabs coins",
  BIG: "Giant numbers",
  CAMPFIRE: "Cozy fire with your mascot",
  RACE: "Today vs this time yesterday",
  CLOCK: "Clock and your streak",
};
const ACTIVITY_ICON: Record<string, string> = {
  nudge: "👉", hype: "👏", message_in: "💬", message_out: "📤", medal: "🏅",
  run: "✅", friend_run: "🏃", remote: "📱",
};
const MESSAGE_MAX = 48;
const EMOJI = ["🔥", "❤️", "👏", "🏃"];
const TOKENS: Record<string, string> = { "[FIRE]": "🔥", "[HEART]": "❤️", "[CLAP]": "👏", "[RUN]": "🏃" };

const pretty = (t: string) => t.replace(/\[(FIRE|HEART|CLAP|RUN)\]/g, (x) => TOKENS[x] ?? x);
const cap = (s: string) => s.charAt(0) + s.slice(1).toLowerCase();

function ago(iso: string | null): string {
  if (!iso) return "never";
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  return `${Math.floor(s / 86400)} d ago`;
}

function boxName(b: Box) {
  return b.label || (b.username ? `@${b.username}'s desk` : "Desk");
}

function storedBox(): string | null {
  try {
    return window.localStorage.getItem(STORE_KEY);
  } catch {
    return null;
  }
}

// ─── the live preview: the box's own code drawing its real feed ─────────────

type Preview = {
  start(feed: string, style: number, mascot: number): void;
  feed(feed: string, now: number): void;
  choose(style: number, mascot: number, now: number): void;
  frame(now: number): Uint8Array;
};

let enginePromise: Promise<Preview> | null = null;

/** Load MicroPython + the desk's code once per page. */
function loadEngine(): Promise<Preview> {
  if (enginePromise) return enginePromise;
  enginePromise = (async () => {
    // Plain dynamic import of a static file (kept out of the bundle).
    const importer = new Function("u", "return import(u)") as (u: string) => Promise<any>;
    const { loadMicroPython } = await importer("/desk/mp/micropython.mjs");
    const mp = await loadMicroPython({ heapsize: 6 * 1024 * 1024 });
    const files = ["displayio.py", "bitmaptools.py", "deskpreview.py",
      ...["__init__", "gfx", "art", "app", "cards", "heat", "fx", "modes", "extra", "decor", "season", "closet"]
        .map((m) => `mad/${m}.py`)];
    mp.FS.mkdir("/mad");
    await Promise.all(files.map(async (f) => {
      const res = await fetch(`/desk/py/${f}`);
      if (!res.ok) throw new Error(`preview file ${f}: ${res.status}`);
      mp.FS.writeFile(`/${f}`, new Uint8Array(await res.arrayBuffer()));
    }));
    mp.runPython("import sys\nif '/' not in sys.path: sys.path.append('/')");
    return mp.pyimport("deskpreview") as Preview;
  })();
  return enginePromise;
}

function LivePreview({ feed, style, mascot }: { feed: Feed; style: number; mascot: number }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const engine = useRef<Preview | null>(null);
  const started = useRef(false);
  const t0 = useRef(0);
  const [state, setState] = useState<"loading" | "ok" | "error">("loading");
  const feedJson = JSON.stringify(feed);

  const now = () => (performance.now() - t0.current) / 1000;

  useEffect(() => {
    let alive = true;
    let raf = 0;
    let last = 0;
    loadEngine()
      .then((eng) => {
        if (!alive) return;
        engine.current = eng;
        t0.current = performance.now();
        eng.start(feedJson, style, mascot);
        started.current = true;
        setState("ok");
        const ctx = canvas.current?.getContext("2d");
        const img = ctx?.createImageData(64, 32);
        const draw = (ts: number) => {
          raf = requestAnimationFrame(draw);
          if (!ctx || !img || ts - last < 66) return;     // ~15 fps, like the box
          last = ts;
          const rgb = eng.frame(now());
          for (let i = 0, j = 0; i < 2048; i++, j += 3) {
            // the panel's palette is dim on purpose (one USB supply); brighten
            // it for a phone screen the way the LEDs read in a room
            img.data[i * 4] = Math.min(255, rgb[j] * 1.8);
            img.data[i * 4 + 1] = Math.min(255, rgb[j + 1] * 1.8);
            img.data[i * 4 + 2] = Math.min(255, rgb[j + 2] * 1.8);
            img.data[i * 4 + 3] = 255;
          }
          ctx.putImageData(img, 0, 0);
        };
        raf = requestAnimationFrame(draw);
      })
      .catch(() => alive && setState("error"));
    return () => {
      alive = false;
      cancelAnimationFrame(raf);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (started.current && engine.current) engine.current.feed(feedJson, now());
  }, [feedJson]);

  useEffect(() => {
    if (started.current && engine.current) engine.current.choose(style, mascot, now());
  }, [style, mascot]);

  return (
    <div className="relative overflow-hidden rounded-xl bg-black p-2">
      <canvas
        ref={canvas}
        width={64}
        height={32}
        className="block w-full"
        style={{ imageRendering: "pixelated", aspectRatio: "2 / 1" }}
      />
      {state !== "ok" && (
        <div className="absolute inset-0 flex items-center justify-center text-xs text-white/50">
          {state === "loading" ? "Drawing the real screen…" : "Preview unavailable"}
        </div>
      )}
    </div>
  );
}

// ─── page ───────────────────────────────────────────────────────────────────

function Section({ title, children, right }: { title: string; children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <section className="rounded-2xl border border-white/10 bg-white/[0.04] p-4">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h2 className="text-sm font-extrabold uppercase tracking-wider text-white/60">{title}</h2>
        {right}
      </div>
      {children}
    </section>
  );
}

export function DeskRemote() {
  const [boxes, setBoxes] = useState<Box[] | null>(null);
  const [boxId, setBoxId] = useState<string | null>(null);
  const [data, setData] = useState<BoxDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [view, setView] = useState<{ style: number; mascot: number } | null>(null);   // previewing
  const [to, setTo] = useState("");
  const [text, setText] = useState("");

  const say = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(null), 3200);
  };

  // boxes, and the one this phone used last
  useEffect(() => {
    getData<{ boxes: Box[] }>("desk/boxes")
      .then(({ boxes }) => {
        setBoxes(boxes);
        const saved = storedBox();
        setBoxId(boxes.find((b) => b.id === saved)?.id ?? boxes[0]?.id ?? null);
      })
      .catch((e) => setError((e as Error).message));
  }, []);

  const load = useCallback(async () => {
    if (!boxId) return;
    try {
      const d = await getData<BoxDetail>(`desk/box/${boxId}`);
      setData(d);
      setError(null);
      setTo((cur) => (d.recipients.some((r) => r.id === cur) ? cur : d.recipients[0]?.id ?? ""));
    } catch (e) {
      setError((e as Error).message);
    }
  }, [boxId]);

  useEffect(() => {
    setData(null);
    setView(null);
    load();
    const id = setInterval(load, 15000);       // the box polls every ~15 s too
    return () => clearInterval(id);
  }, [load]);

  function pickBox(id: string) {
    setBoxId(id);
    try {
      window.localStorage.setItem(STORE_KEY, id);
    } catch {
      /* private mode: just not remembered */
    }
  }

  // What the box is set to (null = whatever its own buttons picked).
  const setStyle = data?.settings.style ?? null;
  const setMascot = data?.settings.mascot ?? null;
  const shown = view ?? { style: setStyle ?? 0, mascot: setMascot ?? 1 };
  const dirty = !!view && (view.style !== setStyle || view.mascot !== setMascot);

  async function apply() {
    if (!data || !view) return;
    setBusy(true);
    try {
      const r = await postData<{ settings: BoxDetail["settings"] }>(`desk/box/${data.box.id}/settings`,
        { style: view.style, mascot: view.mascot });
      setData((d) => (d ? { ...d, settings: r.settings } : d));
      setView(null);
      say(`Sent — ${boxName(data.box)} switches in about 15 seconds`);
      load();
    } catch (e) {
      say((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function statShow() {
    if (!data) return;
    try {
      await postData(`desk/box/${data.box.id}/show`, {});
      say("Stat show starts on the desk in about 15 seconds");
      load();
    } catch (e) {
      say((e as Error).message);
    }
  }

  async function send() {
    if (!data || !to || !text.trim()) return;
    setBusy(true);
    try {
      await postData(`desk/box/${data.box.id}/message`, { to, text });
      setText("");
      const r = data.recipients.find((b) => b.id === to);
      say(`Sent to ${r ? boxName(r) : "that desk"}`);
      load();
    } catch (e) {
      say((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  if (error && !data) {
    return <main className="min-h-screen bg-black p-6 text-white/70">Couldn&apos;t load the desks: {error}</main>;
  }
  if (boxes && boxes.length === 0) {
    return <main className="min-h-screen bg-black p-6 text-white/70">No desks yet — create a key in Admin → Displays.</main>;
  }

  const live = data?.live;
  const owner = data?.box.username;

  return (
    <main
      className="min-h-screen bg-black pb-24 text-white"
      style={{ fontFamily: "ui-rounded, var(--font-nunito), system-ui, sans-serif",
               paddingTop: "max(env(safe-area-inset-top), 16px)" }}
    >
      <div className="mx-auto flex max-w-md flex-col gap-4 px-4">
        {/* ── which box ── */}
        <header className="flex flex-col gap-3 pt-2">
          <h1 className="text-2xl font-extrabold">Desks</h1>
          <div className="flex gap-2 overflow-x-auto">
            {(boxes ?? []).map((b) => (
              <button
                key={b.id}
                onClick={() => pickBox(b.id)}
                className="flex shrink-0 items-center gap-2 rounded-full px-4 py-2 text-sm font-extrabold"
                style={{ background: b.id === boxId ? MAD_RED : "rgba(255,255,255,0.07)" }}
              >
                <span className="h-2 w-2 rounded-full" style={{ background: b.online ? MAD_SUCCESS : "#666" }} />
                {boxName(b)}
              </button>
            ))}
          </div>
          {data && (
            <p className="text-xs text-white/45">
              Shows @{owner}&apos;s data · {data.box.online ? "online now" : `offline · last seen ${ago(data.box.last_seen)}`}
            </p>
          )}
        </header>

        {!data || !live ? (
          <p className="text-sm text-white/40">Loading the desk…</p>
        ) : (
          <>
            {/* ── the real screen ── */}
            <Section title={dirty ? "Preview" : "On the desk"}
                     right={<span className="text-[11px] text-white/40">real data, live</span>}>
              <LivePreview key={data.box.id} feed={live} style={shown.style} mascot={shown.mascot} />
              {setStyle == null && !view && (
                <p className="mt-2 text-xs text-white/45">
                  The desk shows whatever its buttons picked. Choose a style below to set it from here.
                </p>
              )}
              <div className="mt-3 grid grid-cols-2 gap-2">
                {data.mascots.map((m, i) => (
                  <button key={m} disabled={busy}
                          onClick={() => setView({ style: shown.style, mascot: i })}
                          className="rounded-xl py-2.5 text-sm font-extrabold"
                          style={{ background: shown.mascot === i ? MAD_RED : "rgba(255,255,255,0.06)" }}>
                    {m === "FLAMEY" ? "🔥 Flamey" : "🏃 Runner"}
                  </button>
                ))}
              </div>
              <div className="mt-2 grid grid-cols-2 gap-2">
                {data.styles.map((s, i) => (
                  <button key={s} disabled={busy}
                          onClick={() => setView({ style: i, mascot: shown.mascot })}
                          className="rounded-xl px-3 py-2 text-left"
                          style={{ background: shown.style === i ? "rgba(217,64,89,0.25)" : "rgba(255,255,255,0.05)",
                                   boxShadow: shown.style === i ? `inset 0 0 0 1.5px ${MAD_RED}` : undefined }}>
                    <div className="text-sm font-extrabold">
                      {cap(s)} {setStyle === i && <span className="text-[10px] text-white/50">· on desk</span>}
                    </div>
                    <div className="text-[11px] leading-tight text-white/45">{STYLE_INFO[s]}</div>
                  </button>
                ))}
              </div>
              {dirty && (
                <div className="mt-3 grid grid-cols-2 gap-2">
                  <button onClick={() => setView(null)} className="rounded-xl bg-white/[0.08] py-2.5 text-sm font-extrabold">
                    Cancel
                  </button>
                  <button disabled={busy} onClick={apply} className="rounded-xl py-2.5 text-sm font-extrabold"
                          style={{ background: MAD_RED }}>
                    Show on desk
                  </button>
                </div>
              )}
              <button onClick={statShow} className="mt-3 w-full rounded-xl bg-white/[0.08] py-2.5 text-sm font-extrabold">
                ▶ Run the stat show now
              </button>
            </Section>

            {/* ── messages ── */}
            <Section title="Messages">
              {data.recipients.length > 0 ? (
                <div className="flex flex-col gap-2">
                  <div className="flex gap-2">
                    <select value={to} onChange={(e) => setTo(e.target.value)}
                            className="max-w-[45%] rounded-xl bg-white/[0.06] px-3 py-2.5 text-sm font-bold">
                      {data.recipients.map((r) => <option key={r.id} value={r.id}>To {boxName(r)}</option>)}
                    </select>
                    <input value={text} maxLength={MESSAGE_MAX} onChange={(e) => setText(e.target.value)}
                           placeholder="Nice mile!"
                           className="min-w-0 flex-1 rounded-xl bg-white/[0.06] px-3 py-2.5 text-base outline-none" />
                  </div>
                  <div className="flex items-center gap-2">
                    {EMOJI.map((e) => (
                      <button key={e} onClick={() => setText((t) => (t + " " + e).trim().slice(0, MESSAGE_MAX))}
                              className="rounded-xl bg-white/[0.06] px-3 py-2 text-lg">{e}</button>
                    ))}
                    <button disabled={busy || !text.trim()} onClick={send}
                            className="ml-auto rounded-xl px-5 py-2.5 text-sm font-extrabold disabled:opacity-40"
                            style={{ background: MAD_RED }}>Send</button>
                  </div>
                  <p className="text-[11px] text-white/40">
                    From @{owner} · letters, numbers and 🔥 ❤️ 👏 🏃 · {MESSAGE_MAX - text.length} left
                  </p>
                </div>
              ) : (
                <p className="text-sm text-white/50">No other desks to message.</p>
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
            <Section title="Live now" right={<span className="text-[11px] text-white/40">every 15 s</span>}>
              <div className="grid grid-cols-3 gap-2 text-center">
                <Stat label={`@${owner}'s mile`}
                      value={live.me.mile_done ? "Done ✓" : live.me.running_now ? `${(live.me.live_miles ?? 0).toFixed(2)} mi` : "Not yet"}
                      color={live.me.mile_done ? MAD_SUCCESS : undefined} />
                <Stat label="Streak" value={`🔥 ${live.me.streak.toLocaleString()}`} />
                <Stat label="Out now" value={(live.community.out_running_now ?? 0).toLocaleString()} />
                <Stat label="Miles today" value={Math.round(live.community.miles_today ?? 0).toLocaleString()} />
                <Stat label="Users" value={(live.community.total_users ?? 0).toLocaleString()} />
                <Stat label="Hypes today" value={(live.community.hypes_today ?? 0).toLocaleString()} />
              </div>
              <List title="Friends running" empty="No friends out right now"
                    rows={live.friends_running.map((f) => [`@${f.name}`, `${f.miles.toFixed(1)} mi`])} />
              <List title="Just finished" empty="Nobody in the last 30 min"
                    rows={live.friends_finished.map((f) => [`@${f.name}`, `${f.miles.toFixed(1)} mi`])} />
              <List title={`Streaks at risk (${live.friends_at_risk.count})`} empty="Everyone's safe today"
                    rows={live.friends_at_risk.top.map((f) => [`@${f.name}`, `🔥 ${f.streak}`])} />
            </Section>

            {/* ── activity log ── */}
            <Section title="Activity" right={<span className="text-[11px] text-white/40">last 7 days</span>}>
              {data.activity.length === 0 ? (
                <p className="text-sm text-white/40">Nothing yet this week.</p>
              ) : (
                <ul className="flex flex-col">
                  {data.activity.map((a, i) => (
                    <li key={i} className="flex gap-3 border-b border-white/[0.06] py-2 last:border-0">
                      <span className="w-6 shrink-0 text-center">{ACTIVITY_ICON[a.kind] ?? "•"}</span>
                      <span className="min-w-0 flex-1 text-sm">{pretty(a.text)}</span>
                      <span className="shrink-0 text-[11px] text-white/40">{ago(a.at)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </Section>

            <p className="pb-6 text-center text-[11px] text-white/30">
              Tip: in Safari tap Share → Add to Home Screen to open this like an app.
            </p>
          </>
        )}
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
      <div className="truncate text-[10px] font-bold uppercase tracking-wider text-white/40">{label}</div>
    </div>
  );
}

function List({ title, rows, empty }: { title: string; rows: string[][]; empty: string }) {
  return (
    <div className="mt-4">
      <h3 className="mb-1.5 text-xs font-extrabold text-white/70">{title}</h3>
      {rows.length === 0 ? (
        <p className="text-xs text-white/35">{empty}</p>
      ) : (
        <ul className="divide-y divide-white/[0.06]">
          {rows.map(([a, b]) => (
            <li key={a} className="flex justify-between gap-3 py-1.5 text-sm">
              <span className="truncate font-semibold">{a}</span>
              <span className="shrink-0 text-white/60">{b}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
