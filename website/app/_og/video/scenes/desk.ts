import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { createCanvas, type Canvas } from "@napi-rs/canvas";
import { LED_GAIN, MASCOT, STYLE, type DeskEngine } from "@/lib/desk-engine";
import { BRAND } from "../../shared";
import { VIDEO, ogAsset, type Ctx, type Scene } from "../render";
import {
  around,
  beat,
  brandGradient,
  clamp01,
  count,
  ease,
  font,
  foreground,
  ground,
  lerp,
  lockup,
  radialGlow,
  roundRect,
  sparkles,
} from "../kit";

// /desk's video: the desk box itself, running. The panel is drawn by the box's
// OWN code — MicroPython + public/desk/py, the same engine the page's live twin
// runs — fed the real community numbers, so the clip shows exactly what a box
// on someone's desk showed at render time.

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "https://mad.mindgoblin.tech";
const DESK = join(process.cwd(), "public/desk");

/** The desk's MicroPython engine, loaded from public/desk with the filesystem. */
async function nodeDeskEngine(): Promise<DeskEngine> {
  // A real dynamic import of the shipped .mjs (kept out of the bundle).
  const importer = new Function("u", "return import(u)") as (
    u: string,
  ) => Promise<{
    loadMicroPython: (o: object) => Promise<{
      FS: { mkdir(p: string): void; writeFile(p: string, d: Uint8Array): void };
      runPython(code: string): void;
      pyimport(name: string): unknown;
    }>;
  }>;
  const { loadMicroPython } = await importer(
    pathToFileURL(join(DESK, "mp/micropython.mjs")).href,
  );
  const mp = await loadMicroPython({
    heapsize: 6 * 1024 * 1024,
    url: join(DESK, "mp/micropython.wasm"),
  });
  mp.FS.mkdir("/mad");
  const top = ["displayio.py", "bitmaptools.py", "deskpreview.py"];
  const mad = (await readdir(join(DESK, "py/mad"))).filter((f) =>
    f.endsWith(".py"),
  );
  await Promise.all([
    ...top.map(async (f) =>
      mp.FS.writeFile(`/${f}`, await readFile(join(DESK, "py", f))),
    ),
    ...mad.map(async (f) =>
      mp.FS.writeFile(`/mad/${f}`, await readFile(join(DESK, "py/mad", f))),
    ),
  ]);
  mp.runPython("import sys\nif '/' not in sys.path: sys.path.append('/')");
  return mp.pyimport("deskpreview") as DeskEngine;
}

/** The public desk feed (community totals only), or null when it's unreachable. */
async function deskFeed(): Promise<string | null> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 4000);
    const res = await fetch(`${API_URL}/public/desk`, {
      signal: controller.signal,
      cache: "no-store",
    });
    clearTimeout(timer);
    if (!res.ok) return null;
    const text = await res.text();
    JSON.parse(text);
    return text;
  } catch {
    return null;
  }
}

/** The style switch mid-clip: the arcade, then the giant-stat style. */
const SWITCH_AT = 3.2;

export async function deskScene(): Promise<Scene> {
  // No feed, no video: a box with made-up numbers would be a lie, so the
  // route answers with an error and the preview falls back to the PNG.
  const feed = await deskFeed();
  if (!feed) throw new Error("desk feed unavailable");
  const users =
    (JSON.parse(feed).community?.total_users as number | undefined) ?? null;

  const [icon, engine] = await Promise.all([
    ogAsset("icon.png"),
    nodeDeskEngine(),
  ]);
  const today = new Date().toLocaleDateString("en-CA", {
    timeZone: "America/New_York",
  });
  engine.start(feed, STYLE.ARCADE, MASCOT.FLAMEY);
  engine.set_date(today);
  // Every frame up front: the engine is a running program, so its frames
  // must be taken in order however the scene is sampled.
  const { fps, seconds } = VIDEO;
  const frames: Uint8Array[] = [];
  for (let i = 0; i < fps * seconds; i++) {
    const now = 4 + i / fps; // a few seconds in: past any opening transition
    if (i === Math.round(SWITCH_AT * fps))
      engine.choose(STYLE.BIG, MASCOT.FLAMEY, now);
    frames.push(engine.frame(now).slice());
  }

  return (g, t) => {
    ground(g, t);
    foreground(g, t);
    const rgb = frames[Math.min(frames.length - 1, Math.round(t * fps))];

    lockup(g, icon, t);
    const tagIn = ease.outBack(beat(t, 0.2, 0.5));
    around(
      g,
      72,
      175,
      { scale: lerp(0.6, 1, tagIn), alpha: clamp01(tagIn * 2) },
      () => {
        g.font = font.body(22, 700);
        const label = "MILE A DAY DESK";
        const w = g.measureText(label).width + 40;
        roundRect(g, 72, 156, w, 42, 21);
        g.fillStyle = "rgba(199,37,84,0.2)";
        g.fill();
        g.fillStyle = BRAND.pink;
        g.textBaseline = "middle";
        g.fillText(label, 92, 178);
        g.textBaseline = "alphabetic";
      },
    );
    const lines: [string, boolean][] = [
      ["YOUR STREAK,", false],
      ["LIVE ON", false],
      ["YOUR DESK.", true],
    ];
    lines.forEach(([text, red], i) => {
      const p = ease.outQuint(beat(t, 0.35 + i * 0.14, 0.7));
      const y = 296 + i * 84;
      around(g, 72, y, { alpha: p, dy: (1 - p) * 50 }, () => {
        g.font = font.head(96);
        const shine = beat(t, 2.3, 1.1);
        g.fillStyle = red
          ? brandGradient(
              g,
              72,
              480,
              shine > 0 && shine < 1 ? ease.inOutSine(shine) : null,
            )
          : BRAND.ink;
        g.fillText(text, 72, y);
      });
    });
    livePill(g, t, 72, 532, users);

    box(g, t, rgb);

    sparkles(g, t, [
      { x: 1150, y: 110, s: 9, d: 0.6 },
      { x: 600, y: 120, s: 7, d: 2.6 },
      { x: 1140, y: 560, s: 6, d: 3.9 },
    ]);
  };
}

/** "● LIVE · 230 people" — the dot pulsing like a recording light. */
function livePill(
  g: Ctx,
  t: number,
  x: number,
  y: number,
  users: number | null,
) {
  const p = beat(t, 1.2, 0.55);
  const text = users
    ? `Live now · ${count(users)} people on Mile A Day`
    : "Watch it live at mileaday.run/desk";
  g.font = font.body(24, 700);
  const w = 56 + g.measureText(text).width + 26;
  const h = 54;
  around(
    g,
    x + 30,
    y + h / 2,
    { scale: lerp(0.7, 1, ease.outBack(p)), alpha: clamp01(p * 2) },
    () => {
      roundRect(g, x, y, w, h, h / 2);
      g.fillStyle = "rgba(199,37,84,0.16)";
      g.fill();
      g.lineWidth = 2;
      g.strokeStyle = "rgba(199,37,84,0.6)";
      g.stroke();
      const pulse = (Math.sin(t * 5) + 1) / 2;
      radialGlow(g, x + 30, y + h / 2, 20, 0.5 * pulse, "255,77,125");
      g.fillStyle = BRAND.pink;
      g.beginPath();
      g.arc(x + 30, y + h / 2, 7, 0, Math.PI * 2);
      g.fill();
      g.fillStyle = BRAND.ink;
      g.textBaseline = "middle";
      g.font = font.body(24, 700);
      g.fillText(text, x + 56, y + h / 2 + 1);
      g.textBaseline = "alphabetic";
    },
  );
}

/** The box: a dark enclosure around the 64×32 panel, its light spilling below. */
function box(g: Ctx, t: number, rgb: Uint8Array) {
  const pw = 448;
  const ph = 224;
  const bx = 648;
  const by = 176;
  const pad = 22;
  const p = ease.outBack(beat(t, 0.25, 0.9));
  // Still once landed: a moving dot grid re-encodes every pixel of it.
  const bob = 0;

  // The panel's average colour tints the glow under the box.
  let r = 0;
  let gg = 0;
  let b = 0;
  for (let i = 0; i < rgb.length; i += 3) {
    r += rgb[i];
    gg += rgb[i + 1];
    b += rgb[i + 2];
  }
  const n = rgb.length / 3;
  const tint = [r, gg, b]
    .map((c) => Math.min(255, Math.round((c / n) * LED_GAIN * 6)))
    .join(",");

  around(
    g,
    bx + pw / 2,
    by + ph / 2,
    {
      scale: lerp(0.75, 1, p),
      alpha: clamp01(p * 2),
      dx: (1 - p) * 120,
      dy: bob,
    },
    () => {
      radialGlow(g, bx + pw / 2, by + ph + pad + 40, 300, 0.32, tint);
      g.save();
      g.shadowColor = "rgba(0,0,0,0.7)";
      g.shadowBlur = 60;
      g.shadowOffsetY = 24;
      roundRect(g, bx - pad, by - pad, pw + pad * 2, ph + pad * 2, 26);
      const body = g.createLinearGradient(0, by - pad, 0, by + ph + pad);
      body.addColorStop(0, "#232326");
      body.addColorStop(1, "#111113");
      g.fillStyle = body;
      g.fill();
      g.restore();
      g.lineWidth = 2;
      g.strokeStyle = "rgba(255,255,255,0.1)";
      roundRect(g, bx - pad, by - pad, pw + pad * 2, ph + pad * 2, 26);
      g.stroke();
      leds(g, rgb, bx, by, pw, ph);
      // Glass sheen.
      const sheen = g.createLinearGradient(bx, by, bx + pw * 0.6, by + ph);
      sheen.addColorStop(0, "rgba(255,255,255,0.06)");
      sheen.addColorStop(0.5, "rgba(255,255,255,0)");
      g.fillStyle = sheen;
      g.fillRect(bx, by, pw, ph);
    },
  );
}

const small = createCanvas(64, 32);
const smallCtx = small.getContext("2d");
const smallPixels = smallCtx.createImageData(64, 32);
const masks = new Map<string, Canvas>();

/**
 * The panel as LEDs — the look of lib/desk-engine's `drawLeds` (round dots on
 * a black board, unlit ones faintly visible, a glow round lit ones), built
 * from three image draws instead of ~2,000 arcs a frame, which Skia on a
 * server takes ages over: the 64×32 frame scaled up blocky, a board with
 * round holes over it, then the frame again, smoothed, as light.
 */
function leds(
  g: Ctx,
  rgb: Uint8Array,
  x: number,
  y: number,
  w: number,
  h: number,
) {
  const d = smallPixels.data;
  for (let i = 0, j = 0; i < 2048; i++, j += 3) {
    const lit = rgb[j] | rgb[j + 1] | rgb[j + 2];
    d[i * 4] = lit ? Math.min(255, rgb[j] * LED_GAIN) : 0x1d;
    d[i * 4 + 1] = lit ? Math.min(255, rgb[j + 1] * LED_GAIN) : 0x1d;
    d[i * 4 + 2] = lit ? Math.min(255, rgb[j + 2] * LED_GAIN) : 0x1d;
    d[i * 4 + 3] = 255;
  }
  smallCtx.putImageData(smallPixels, 0, 0);
  g.save();
  g.imageSmoothingEnabled = false;
  g.drawImage(small, x, y, w, h);
  g.imageSmoothingEnabled = true;
  g.drawImage(boardMask(w, h), x, y);
  g.globalCompositeOperation = "lighter";
  g.globalAlpha *= 0.28;
  const p = w / 64;
  g.drawImage(small, x - p, y - p, w + 2 * p, h + 2 * p);
  g.restore();
}

/** The black board with a round hole per LED (cached per size). */
function boardMask(w: number, h: number): Canvas {
  const key = `${w}x${h}`;
  const hit = masks.get(key);
  if (hit) return hit;
  const c = createCanvas(Math.ceil(w), Math.ceil(h));
  const m = c.getContext("2d");
  m.fillStyle = "#050505";
  m.fillRect(0, 0, w, h);
  m.globalCompositeOperation = "destination-out";
  const p = w / 64;
  m.beginPath();
  for (let yy = 0; yy < 32; yy++) {
    for (let xx = 0; xx < 64; xx++) {
      const cx = (xx + 0.5) * p;
      const cy = (yy + 0.5) * p;
      m.moveTo(cx + p * 0.36, cy);
      m.arc(cx, cy, p * 0.36, 0, Math.PI * 2);
    }
  }
  m.fill();
  masks.set(key, c);
  return c;
}
