"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getData, postData } from "./lib";
import { MAD_RED, MAD_SUCCESS } from "./theme";
import { loadDeskEngine, type DeskEngine } from "@/lib/desk-engine";
import { ShareClip } from "@/components/desk/share-clip";
import { PushSettings } from "@/components/desk/push-settings";

/**
 * The desk remote (/admin/desk), phone-first. Your own box(es) only,
 * then: see its REAL screen (the box's own code, running here in MicroPython
 * WebAssembly on the box's real feed, so the numbers, Flamey's closet look and
 * the season are exactly what's on the desk), set its style and mascot, start
 * its stat show, message another box, and read what happened on it.
 *
 * Nothing here can fake an event: nudges, hypes, runs, medals and messages
 * only ever come from real activity. The chosen box is remembered per phone.
 */

type BoxState = { style: number; mascot: number; awake: boolean; sleep_start: number | null; sleep_end: number | null };
type Box = { id: string; label: string; username: string | null; last_seen: string | null; online: boolean;
             state: BoxState | null };

/** Names for the test animations (the box's own list, testscenes.py). */
const TEST_LABEL: Record<string, string> = {
  user: "New user", milestone: "User milestone", nudge: "Nudge", hype: "Hype",
  friend: "Friend running", friend_walk: "Friend walking", finished: "Friend finished",
  friendmile: "Mile in!", atrisk: "Streaks at risk", reminder: "Mile reminder",
  morning: "Good morning", mile: "Mile done", streak: "Streak milestone",
  yearago: "1 year ago", pr: "New PR", message: "Message", comment: "Comment",
  medal: "New medal", review: "App review", recap: "9pm recap", holiday: "Holiday",
  newyear: "New Year", countdown: "New Year countdown", lead: "Lead change",
  doodle: "Doodle", record: "Signup record", replay: "Run replay", dizzy: "Shaken (dizzy)",
};

type Kind = "run" | "walk";
const kindLabel = (k?: Kind | null, done = false) =>
  k === "walk" ? (done ? "🚶 walk" : "🚶 walking") : (done ? "🏃 run" : "🏃 running");

type Feed = {
  community: Record<string, number>;
  me: {
    username: string | null;
    mile_done: boolean;
    miles_today: number;
    streak: number;
    running_now: boolean;
    live_miles: number | null;
    live_kind?: Kind | null;
    local_time: string;
    miles_week?: number;
  };
  friends_running: { name: string; miles: number; kind?: Kind }[];
  friends_finished: { id: string; name: string; miles: number; kind?: Kind }[];
  friends_at_risk: { count: number; top: { name: string; streak: number }[] };
  rival?: { name: string; miles_today: number; miles_week: number; streak: number; mile_done: boolean } | null;
  growth?: { today: number; yesterday_same_time: number; week: number[]; dows: string; best_30: number } | null;
};

type BoxDetail = {
  box: Box;
  styles: string[];
  tests?: string[];
  mascots: string[];
  settings: { style: number | null; mascot: number | null; rev: number;
              sleep_start: number | null; sleep_end: number | null; never_sleep: boolean };
  messages: { id: string; direction: "in" | "out"; who: string; text: string; at: string }[];
  recipients: Recipient[];
  activity: { at: string; kind: string; text: string; px?: string }[];
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
  VERSUS: "You vs your friend's desk: today, week, streak",
  GROWTH: "Signups today and this week",
  ODOMETER: "Every mile ever logged, on rolling wheels",
  SHOWCASE: "Cycles every style, with a stat show (booths and demos)",
};
const ACTIVITY_ICON: Record<string, string> = {
  nudge: "👉", hype: "👏", message_in: "💬", message_out: "📤", medal: "🏅",
  run: "✅", friend_run: "🏃", friend_mile: "🎉", remote: "📱", doodle_in: "🎨", doodle_out: "🖌️",
  new_user: "🙋", interest: "📦",
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

const toHHMM = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
const fromHHMM = (v: string) => {
  const [h, m] = v.split(":").map(Number);
  return Number.isFinite(h) && Number.isFinite(m) ? h * 60 + m : null;
};
function niceTime(m: number) {
  const h = Math.floor(m / 60), mm = m % 60;
  return `${((h + 11) % 12) + 1}:${String(mm).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}

type Recipient = Pick<Box, "id" | "label" | "username">;

function boxName(b: Recipient) {
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

type Preview = DeskEngine;
const loadEngine = loadDeskEngine;

/** `sleep`: the box's hours ([-1,-1] = never sleeps) and whether it's awake;
 *  `forceAwake` while previewing a new look (show it as it looks by day). */
function LivePreview({ feed, style, mascot, sleep, forceAwake, test, doodle, frameRef }: {
  feed: Feed; style: number; mascot: number;
  sleep: { awake: boolean; start: number; end: number }; forceAwake: boolean;
  test?: { scene: string; n: number } | null;
  doodle?: { code: string; n: number } | null;
  frameRef?: React.MutableRefObject<Uint8Array | null>;
}) {
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
        eng.sleep(forceAwake || sleep.awake ? 1 : 0, sleep.start, sleep.end, now());
        started.current = true;
        setState("ok");
        const ctx = canvas.current?.getContext("2d");
        const img = ctx?.createImageData(64, 32);
        const draw = (ts: number) => {
          raf = requestAnimationFrame(draw);
          if (!ctx || !img || ts - last < 40) return;     // ~24 fps, like the box
          last = ts;
          const rgb = eng.frame(now());
          if (frameRef) frameRef.current = rgb;
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

  useEffect(() => {
    if (test && started.current && engine.current) engine.current.test(test.scene, now());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [test?.n]);

  useEffect(() => {
    if (doodle && started.current && engine.current) engine.current.doodle(doodle.code, now());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [doodle?.n]);

  const awakeNow = forceAwake || sleep.awake;
  useEffect(() => {
    if (started.current && engine.current) engine.current.sleep(awakeNow ? 1 : 0, sleep.start, sleep.end, now());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [awakeNow, sleep.start, sleep.end]);

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

// ─── doodles ────────────────────────────────────────────────────────────────

/** The box's 8 doodle colours (digit = index), as the preview brightens them. */
const INKS = ["#000000", "#ffffc9", "#ff0000", "#fcc927", "#fc9a0c", "#00ff00", "#489eff", "#731dac"];
const INK_NAMES = ["Eraser", "White", "Red", "Gold", "Orange", "Green", "Blue", "Purple"];
const DW = 64;
const DH = 32;
const RUN = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_";
const DOODLE_MAX_CODE = 1600;   // the server's limit (keeps the box's feed small)

/** Run-length code, exactly as the server sends it to the box. */
function doodleCode(px: string): string {
  let out = "";
  for (let i = 0; i < px.length;) {
    let n = 1;
    while (n < 64 && i + n < px.length && px[i + n] === px[i]) n++;
    out += px[i] + RUN[n - 1];
    i += n;
  }
  return out;
}

function DoodlePad({ busy, recipients, to, setTo, onPreview, onSend }: {
  busy: boolean; recipients: Recipient[]; to: string; setTo: (id: string) => void;
  onPreview: (code: string) => void; onSend: (px: string) => Promise<boolean>;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const px = useRef<Uint8Array>(new Uint8Array(DW * DH));
  const undo = useRef<Uint8Array[]>([]);
  const last = useRef<{ x: number; y: number } | null>(null);
  const [ink, setInk] = useState(2);
  const [thick, setThick] = useState(false);
  const [count, setCount] = useState(0);        // lit pixels
  const [size, setSize] = useState(0);          // coded length

  const paint = useCallback(() => {
    const ctx = canvas.current?.getContext("2d");
    if (!ctx) return;
    const img = ctx.createImageData(DW, DH);
    let lit = 0;
    for (let i = 0; i < DW * DH; i++) {
      const c = INKS[px.current[i]];
      img.data[i * 4] = parseInt(c.slice(1, 3), 16);
      img.data[i * 4 + 1] = parseInt(c.slice(3, 5), 16);
      img.data[i * 4 + 2] = parseInt(c.slice(5, 7), 16);
      img.data[i * 4 + 3] = 255;
      if (px.current[i]) lit++;
    }
    ctx.putImageData(img, 0, 0);
    setCount(lit);
    setSize(doodleCode(Array.from(px.current).join("")).length);
  }, []);

  useEffect(paint, [paint]);

  const dot = (x: number, y: number) => {
    const r = thick ? 1 : 0;
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        const xx = x + dx, yy = y + dy;
        if (xx >= 0 && xx < DW && yy >= 0 && yy < DH) px.current[yy * DW + xx] = ink;
      }
    }
  };

  const at = (e: React.PointerEvent) => {
    const r = canvas.current!.getBoundingClientRect();
    return { x: Math.floor(((e.clientX - r.left) / r.width) * DW), y: Math.floor(((e.clientY - r.top) / r.height) * DH) };
  };

  const down = (e: React.PointerEvent) => {
    e.preventDefault();
    canvas.current?.setPointerCapture(e.pointerId);
    undo.current = [...undo.current.slice(-19), px.current.slice()];
    const p = at(e);
    dot(p.x, p.y);
    last.current = p;
    paint();
  };
  const move = (e: React.PointerEvent) => {
    if (!last.current) return;
    const p = at(e);
    const a = last.current;
    const steps = Math.max(Math.abs(p.x - a.x), Math.abs(p.y - a.y), 1);
    for (let k = 1; k <= steps; k++) {          // a line, so fast strokes don't skip
      dot(Math.round(a.x + ((p.x - a.x) * k) / steps), Math.round(a.y + ((p.y - a.y) * k) / steps));
    }
    last.current = p;
    paint();
  };
  const up = () => { last.current = null; };

  const clear = () => {
    undo.current = [...undo.current.slice(-19), px.current.slice()];
    px.current = new Uint8Array(DW * DH);
    paint();
  };
  const back = () => {
    const prev = undo.current.pop();
    if (prev) { px.current = prev; paint(); }
  };

  const tooBusy = size > DOODLE_MAX_CODE;
  const text = Array.from(px.current).join("");

  return (
    <div className="flex flex-col gap-2">
      <canvas ref={canvas} width={DW} height={DH}
              onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up}
              className="block w-full touch-none rounded-lg"
              style={{ imageRendering: "pixelated", aspectRatio: "2 / 1", boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.15)" }} />
      <div className="flex flex-wrap items-center gap-1.5">
        {INKS.map((c, i) => (
          <button key={c} aria-label={INK_NAMES[i]} title={INK_NAMES[i]} onClick={() => setInk(i)}
                  className="h-8 w-8 rounded-full text-xs"
                  style={{ background: i ? c : "rgba(255,255,255,0.08)",
                           boxShadow: ink === i ? `0 0 0 2px #000, 0 0 0 4px ${MAD_RED}` : "inset 0 0 0 1px rgba(255,255,255,0.2)" }}>
            {i === 0 ? "⌫" : ""}
          </button>
        ))}
        <button onClick={() => setThick((t) => !t)} className="ml-auto rounded-lg bg-white/[0.08] px-2.5 py-1.5 text-xs font-bold">
          {thick ? "Thick" : "Thin"}
        </button>
      </div>
      <div className="grid grid-cols-3 gap-2">
        <button onClick={back} className="rounded-xl bg-white/[0.08] py-2 text-sm font-extrabold">Undo</button>
        <button onClick={clear} className="rounded-xl bg-white/[0.08] py-2 text-sm font-extrabold">Clear</button>
        <button disabled={!count || tooBusy} onClick={() => onPreview(doodleCode(text))}
                className="rounded-xl bg-white/[0.08] py-2 text-sm font-extrabold disabled:opacity-40">Preview</button>
      </div>
      {recipients.length > 0 ? (
        <div className="flex gap-2">
          <select value={to} onChange={(e) => setTo(e.target.value)}
                  className="min-w-0 flex-1 rounded-xl bg-white/[0.06] px-3 py-2.5 text-sm font-bold">
            {recipients.map((r) => <option key={r.id} value={r.id}>To {boxName(r)}</option>)}
          </select>
          <button disabled={busy || !count || tooBusy || !to}
                  onClick={async () => { if (await onSend(text)) clear(); }}
                  className="rounded-xl px-5 py-2.5 text-sm font-extrabold disabled:opacity-40"
                  style={{ background: MAD_RED }}>Send</button>
        </div>
      ) : (
        <p className="text-sm text-white/50">No other desks to send to.</p>
      )}
      <p className="text-[11px] text-white/40">
        {tooBusy ? "Too detailed for the box: try bigger shapes or fewer colours."
          : "Only the pixels are sent. It fades in on their desk like a postcard, then goes back to their screen."}
      </p>
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
  const [testReq, setTestReq] = useState<{ scene: string; n: number } | null>(null);
  const [view, setView] = useState<{ style: number; mascot: number } | null>(null);   // previewing
  const [to, setTo] = useState("");
  const [text, setText] = useState("");
  const [doodleReq, setDoodleReq] = useState<{ code: string; n: number } | null>(null);
  const frameRef = useRef<Uint8Array | null>(null);

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
  const st = data?.box.state ?? null;      // what's on the box's screen right now
  const onDesk = st ? { style: st.style, mascot: st.mascot } : { style: setStyle ?? 0, mascot: setMascot ?? 1 };
  const shown = view ?? onDesk;
  // Sleep: the hours the box reports using, else the remote's, else 10pm–7am.
  const sset = data?.settings;
  const hours = st ? { start: st.sleep_start ?? -1, end: st.sleep_end ?? -1 }
    : sset?.never_sleep ? { start: -1, end: -1 }
    : { start: sset?.sleep_start ?? 22 * 60, end: sset?.sleep_end ?? 7 * 60 };
  const awake = st ? st.awake : true;
  const dirty = !!view && (view.style !== onDesk.style || view.mascot !== onDesk.mascot);

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

  async function saveSleep(sleep: { start: number; end: number } | "never" | "default") {
    if (!data) return;
    setBusy(true);
    try {
      const r = await postData<{ settings: BoxDetail["settings"] }>(`desk/box/${data.box.id}/settings`, { sleep });
      setData((d) => (d ? { ...d, settings: r.settings } : d));
      say(sleep === "never" ? "It will stay awake all night"
        : sleep === "default" ? "Back to the box's own sleep hours"
        : `Sleeps ${niceTime(sleep.start)} – wakes ${niceTime(sleep.end)}`);
      load();
    } catch (e) {
      say((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function wakeUp() {
    if (!data) return;
    try {
      await postData(`desk/box/${data.box.id}/wake`, {});
      say("Waking up — bright for 30 minutes (in about 15 seconds)");
      load();
    } catch (e) {
      say((e as Error).message);
    }
  }

  async function testOnBox() {
    if (!data || !testReq) return;
    try {
      await postData(`desk/box/${data.box.id}/test`, { scene: testReq.scene });
      say(`Plays on your desk in about 15 seconds: ${TEST_LABEL[testReq.scene] ?? testReq.scene}`);
      load();
    } catch (e) {
      say((e as Error).message);
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

  async function sendDoodle(px: string): Promise<boolean> {
    if (!data || !to) return false;
    setBusy(true);
    try {
      await postData(`desk/box/${data.box.id}/doodle`, { to, px });
      const r = data.recipients.find((b) => b.id === to);
      say(`Doodle sent to ${r ? boxName(r) : "that desk"}`);
      load();
      return true;
    } catch (e) {
      say((e as Error).message);
      return false;
    } finally {
      setBusy(false);
    }
  }

  if (error && !data) {
    return <main className="min-h-screen bg-black p-6 text-white/70">Couldn&apos;t load the desks: {error}</main>;
  }
  if (boxes && boxes.length === 0) {
    return <main className="min-h-screen bg-black p-6 text-white/70">No desk is linked to your account yet. Make a display key for your own username in Admin → Displays.</main>;
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
              Shows @{owner}&apos;s data · {data.box.online
                ? (st ? (st.awake ? "awake" : `asleep${hours.end >= 0 ? ` · wakes ${niceTime(hours.end)}` : ""}`) : "online now")
                : `offline · last seen ${ago(data.box.last_seen)}`}
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
              <LivePreview key={data.box.id} feed={live} style={shown.style} mascot={shown.mascot}
                           sleep={{ awake, start: hours.start, end: hours.end }} forceAwake={dirty}
                           test={testReq} doodle={doodleReq} frameRef={frameRef} />
              {!st && (
                <p className="mt-2 text-xs text-white/45">
                  {data.box.online ? "This box hasn't reported its screen yet (it needs the latest firmware)."
                    : "This box is offline, so this is its last known setting."}
                </p>
              )}
              {dirty && !awake && (
                <p className="mt-2 text-xs text-white/45">Previewing how it looks awake.</p>
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
                {data.styles.map((s, i) => {
                  const missing = s === "VERSUS" && !live.rival ? "Needs a friend with a desk who shares runs"
                    : s === "GROWTH" && !live.growth ? "Admins only" : null;
                  return (
                  <button key={s} disabled={busy || !!missing}
                          onClick={() => setView({ style: i, mascot: shown.mascot })}
                          className="rounded-xl px-3 py-2 text-left"
                          style={{ background: shown.style === i ? "rgba(217,64,89,0.25)" : "rgba(255,255,255,0.05)",
                                   boxShadow: shown.style === i ? `inset 0 0 0 1.5px ${MAD_RED}` : undefined }}>
                    <div className="text-sm font-extrabold">
                      {cap(s)} {onDesk.style === i && <span className="text-[10px] text-white/50">· on desk</span>}
                    </div>
                    <div className="text-[11px] leading-tight text-white/45">
                      {missing ?? (s === "VERSUS" && live.rival ? `You vs @${live.rival.name}: today, week, streak` : STYLE_INFO[s])}
                    </div>
                  </button>
                  );
                })}
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

            {/* ── share a clip ── */}
            <Section title="Share as GIF or video" right={<span className="text-[11px] text-white/40">for Instagram / TikTok</span>}>
              <ShareClip frameRef={frameRef} />
            </Section>

            {/* ── test animations ── */}
            <Section title="Test animations"
                     right={<span className="text-[11px] text-white/40">plays in the preview above</span>}>
              <p className="mb-2 text-xs text-white/45">
                Tap one to watch it above. To see it on your desk too, tap Play on my box. It shows
                TEST where a name would be, so it can&apos;t be mistaken for a real nudge or hype.
              </p>
              <div className="grid grid-cols-2 gap-1.5">
                {(data.tests ?? []).map((sc) => (
                  <button key={sc}
                          onClick={() => setTestReq((r) => ({ scene: sc, n: (r?.n ?? 0) + 1 }))}
                          className="rounded-lg px-2.5 py-2 text-left text-[13px] font-bold"
                          style={{ background: testReq?.scene === sc ? "rgba(217,64,89,0.25)" : "rgba(255,255,255,0.05)",
                                   boxShadow: testReq?.scene === sc ? `inset 0 0 0 1.5px ${MAD_RED}` : undefined }}>
                    {TEST_LABEL[sc] ?? sc}
                  </button>
                ))}
              </div>
              <button disabled={!testReq} onClick={testOnBox}
                      className="mt-3 w-full rounded-xl py-2.5 text-sm font-extrabold disabled:opacity-40"
                      style={{ background: MAD_RED }}>
                {testReq ? `▶ Play “${TEST_LABEL[testReq.scene] ?? testReq.scene}” on my box` : "Pick one to play it on your box"}
              </button>
            </Section>

            {/* ── sleep ── */}
            <SleepSection
              key={`sleep-${data.box.id}`}
              settings={data.settings}
              hours={hours}
              awake={awake}
              reported={!!st}
              busy={busy}
              onSave={saveSleep}
              onWake={wakeUp}
            />

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

            {/* ── doodles ── */}
            <Section title="Doodle" right={<span className="text-[11px] text-white/40">64 × 32, like the screen</span>}>
              <DoodlePad busy={busy} recipients={data.recipients} to={to} setTo={setTo}
                         onPreview={(code) => setDoodleReq((r) => ({ code, n: (r?.n ?? 0) + 1 }))}
                         onSend={sendDoodle} />
            </Section>

            {/* ── live ── */}
            <Section title="Live now" right={<span className="text-[11px] text-white/40">every 15 s</span>}>
              <div className="grid grid-cols-3 gap-2 text-center">
                <Stat label={`@${owner}'s mile`}
                      value={live.me.mile_done ? "Done ✓" : live.me.running_now
                        ? `${(live.me.live_miles ?? 0).toFixed(2)} mi ${live.me.live_kind === "walk" ? "🚶" : "🏃"}` : "Not yet"}
                      color={live.me.mile_done ? MAD_SUCCESS : undefined} />
                <Stat label="Streak" value={`🔥 ${live.me.streak.toLocaleString()}`} />
                <Stat label="Out now" value={(live.community.out_running_now ?? 0).toLocaleString()} />
                <Stat label="Miles today" value={Math.round(live.community.miles_today ?? 0).toLocaleString()} />
                <Stat label="Users" value={(live.community.total_users ?? 0).toLocaleString()} />
                <Stat label="Hypes today" value={(live.community.hypes_today ?? 0).toLocaleString()} />
              </div>
              <RunsVsWalks c={live.community} />
              {live.rival && (
                <List title="Head to head" empty=""
                      rows={[[`@${owner}`, `${live.me.miles_today.toFixed(2)} today · ${(live.me.miles_week ?? 0).toFixed(1)} this week · 🔥 ${live.me.streak}`],
                             [`@${live.rival.name}`, `${live.rival.miles_today.toFixed(2)} today · ${live.rival.miles_week.toFixed(1)} this week · 🔥 ${live.rival.streak}`]]} />
              )}
              {live.growth && (
                <List title="Signups" empty=""
                      rows={[["Today", `${live.growth.today} (yesterday by now: ${live.growth.yesterday_same_time})`],
                             ["Last 7 days", `${live.growth.week.reduce((a, b) => a + b, 0)} · best day in 30: ${live.growth.best_30}`]]} />
              )}
              <List title="Friends out now" empty="No friends out right now"
                    rows={live.friends_running.map((f) => [`@${f.name}`, `${kindLabel(f.kind)} · ${f.miles.toFixed(1)} mi`])} />
              <List title="Just finished" empty="Nobody in the last 30 min"
                    rows={live.friends_finished.map((f) => [`@${f.name}`, `${f.miles.toFixed(1)} mi ${kindLabel(f.kind, true)}`])} />
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
                      <span className="min-w-0 flex-1 text-sm">
                        {pretty(a.text)}
                        {a.px && /^[0-7]{2048}$/.test(a.px) && (
                          <button onClick={() => { setDoodleReq((r) => ({ code: doodleCode(a.px!), n: (r?.n ?? 0) + 1 }));
                                                   say("Playing it in the preview at the top"); }}
                                  className="mt-1.5 block" aria-label="Play this doodle in the preview">
                            <DoodleThumb px={a.px} />
                          </button>
                        )}
                      </span>
                      <span className="shrink-0 text-[11px] text-white/40">{ago(a.at)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </Section>

            <Section title="Notifications" right={<span className="text-[11px] text-white/40">this phone</span>}>
              <PushSettings say={say} />
            </Section>

            <InterestList />

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

/** A doodle as it looks on the panel (its 8 colours), small. */
function DoodleThumb({ px }: { px: string }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const ctx = ref.current?.getContext("2d");
    if (!ctx) return;
    const img = ctx.createImageData(DW, DH);
    for (let i = 0; i < DW * DH; i++) {
      const c = INKS[Number(px[i]) || 0];
      img.data[i * 4] = parseInt(c.slice(1, 3), 16);
      img.data[i * 4 + 1] = parseInt(c.slice(3, 5), 16);
      img.data[i * 4 + 2] = parseInt(c.slice(5, 7), 16);
      img.data[i * 4 + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
  }, [px]);
  return <canvas ref={ref} width={DW} height={DH} className="w-40 rounded-md"
                 style={{ imageRendering: "pixelated", aspectRatio: "2 / 1", boxShadow: "0 0 0 1px rgba(255,255,255,0.12)" }} />;
}

/** "I'd buy one" signups from mileaday.run/desk (both founders see them). */
function InterestList() {
  const [d, setD] = useState<{ total: number; prices: Record<string, number>;
                               rows: { name: string; email: string; price: string | null; created_at: string }[] } | null>(null);
  const [open, setOpen] = useState(false);
  useEffect(() => {
    getData<NonNullable<typeof d>>("desk/interest").then(setD).catch(() => setD(null));
  }, []);
  if (!d) return null;
  const copy = () => {
    const csv = ["name,email,price,signed_up", ...d.rows.map((r) =>
      [r.name, r.email, r.price ?? "", r.created_at].map((v) => `"${String(v).replace(/"/g, '""')}"`).join(","))].join("\n");
    navigator.clipboard?.writeText(csv);
  };
  return (
    <Section title={`Want one? (${d.total})`} right={<span className="text-[11px] text-white/40">mileaday.run/desk</span>}>
      <div className="grid grid-cols-4 gap-1.5 text-center">
        {["79", "99", "129+", "none"].map((p) => (
          <Stat key={p} label={p === "none" ? "No answer" : `$${p}`} value={String(d.prices[p] ?? 0)} />
        ))}
      </div>
      {d.rows.length > 0 && (
        <>
          <button onClick={() => setOpen((o) => !o)} className="mt-3 w-full rounded-xl bg-white/[0.06] py-2 text-sm font-bold">
            {open ? "Hide the list" : `Show all ${d.rows.length}`}
          </button>
          {open && (
            <>
              <ul className="mt-2 flex flex-col">
                {d.rows.map((r) => (
                  <li key={r.email} className="flex gap-2 border-b border-white/[0.06] py-2 text-sm last:border-0">
                    <span className="min-w-0 flex-1 truncate">
                      <span className="font-bold">{r.name}</span> <span className="text-white/50">{r.email}</span>
                    </span>
                    <span className="shrink-0 text-white/60">{r.price ? `$${r.price}` : "–"}</span>
                    <span className="shrink-0 text-[11px] text-white/40">{ago(r.created_at)}</span>
                  </li>
                ))}
              </ul>
              <button onClick={copy} className="mt-2 w-full rounded-xl bg-white/[0.06] py-2 text-xs font-bold">Copy as CSV</button>
            </>
          )}
        </>
      )}
    </Section>
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

/** Runs vs walks, today and all time: the same two charts as the box's card. */
function RunsVsWalks({ c }: { c: Record<string, number> }) {
  if (c.run_miles_total == null) return null;            // an older server
  const charts: [string, number, number][] = [
    ["Today", c.run_miles_today ?? 0, c.walk_miles_today ?? 0],
    ["All time", c.run_miles_total ?? 0, c.walk_miles_total ?? 0],
  ];
  const fmt = (v: number) => (v >= 1000 ? Math.round(v).toLocaleString() : v.toFixed(1));
  return (
    <div className="mt-4">
      <h3 className="mb-1.5 text-xs font-extrabold text-white/70">Runs vs walks (miles)</h3>
      <div className="grid grid-cols-2 gap-3">
        {charts.map(([title, run, walk]) => {
          const top = Math.max(run, walk) || 1;
          return (
            <div key={title} className="rounded-xl bg-white/[0.04] p-2.5">
              <div className="mb-1.5 text-[11px] font-bold text-white/50">{title}</div>
              {([["Run", run, MAD_RED], ["Walk", walk, "#3B82F6"]] as const).map(([label, v, color]) => (
                <div key={label} className="mb-1 last:mb-0">
                  <div className="flex justify-between text-[11px]">
                    <span className="font-semibold" style={{ color }}>{label}</span>
                    <span className="tabular-nums text-white/70">{fmt(v)}</span>
                  </div>
                  <div className="h-1.5 rounded-full bg-white/[0.06]">
                    <div className="h-1.5 rounded-full" style={{ width: `${(100 * v) / top}%`, background: color }} />
                  </div>
                </div>
              ))}
            </div>
          );
        })}
      </div>
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

function SleepSection({ settings, hours, awake, reported, busy, onSave, onWake }: {
  settings: BoxDetail["settings"];
  hours: { start: number; end: number };
  awake: boolean;
  reported: boolean;
  busy: boolean;
  onSave: (s: { start: number; end: number } | "never" | "default") => void;
  onWake: () => void;
}) {
  const never = hours.start < 0;
  const [start, setStart] = useState(toHHMM(never ? 22 * 60 : hours.start));
  const [end, setEnd] = useState(toHHMM(never ? 7 * 60 : hours.end));
  const a = fromHHMM(start), b = fromHHMM(end);
  const changed = never || a !== hours.start || b !== hours.end;
  return (
    <section className="rounded-2xl border border-white/10 bg-white/[0.04] p-4">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h2 className="text-sm font-extrabold uppercase tracking-wider text-white/60">Sleep</h2>
        <span className="text-[11px] text-white/40">
          {reported ? (awake ? "awake now" : "asleep now") : "dims and shows a clock"}
        </span>
      </div>
      <button
        onClick={onWake}
        className="mb-3 w-full rounded-xl py-2.5 text-sm font-extrabold"
        style={{ background: !awake ? MAD_RED : "rgba(255,255,255,0.08)" }}
      >
        ☀️ Wake it up now (30 min)
      </button>
      <label className="flex items-center justify-between rounded-xl bg-white/[0.05] px-3 py-2.5">
        <span className="text-sm font-bold">Never sleep (always bright)</span>
        <input
          type="checkbox"
          checked={never}
          disabled={busy}
          onChange={(e) => onSave(e.target.checked ? "never" : { start: a ?? 1320, end: b ?? 420 })}
          className="h-5 w-5 accent-[#d94059]"
        />
      </label>
      {!never && (
        <div className="mt-3 grid grid-cols-2 gap-2">
          <label className="rounded-xl bg-white/[0.05] px-3 py-2">
            <div className="text-[10px] font-bold uppercase tracking-wider text-white/40">Goes to sleep</div>
            <input type="time" value={start} onChange={(e) => setStart(e.target.value)}
                   className="w-full bg-transparent text-base font-extrabold outline-none" />
          </label>
          <label className="rounded-xl bg-white/[0.05] px-3 py-2">
            <div className="text-[10px] font-bold uppercase tracking-wider text-white/40">Wakes up</div>
            <input type="time" value={end} onChange={(e) => setEnd(e.target.value)}
                   className="w-full bg-transparent text-base font-extrabold outline-none" />
          </label>
        </div>
      )}
      {!never && changed && a != null && b != null && a !== b && (
        <button disabled={busy} onClick={() => onSave({ start: a, end: b })}
                className="mt-2 w-full rounded-xl py-2.5 text-sm font-extrabold" style={{ background: MAD_RED }}>
          Save sleep hours
        </button>
      )}
      {(settings.never_sleep || settings.sleep_start != null) && (
        <button disabled={busy} onClick={() => onSave("default")} className="mt-2 w-full text-xs font-bold text-white/45">
          Use the box&apos;s own sleep hours instead
        </button>
      )}
      <p className="mt-2 text-[11px] text-white/35">Times are the box owner&apos;s local time. A button press on the box also wakes it for 2 minutes.</p>
    </section>
  );
}
