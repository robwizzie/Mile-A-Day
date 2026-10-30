import { Path2D, type Image } from "@napi-rs/canvas";
import { BRAND } from "../shared";
import { VIDEO, type Ctx } from "./render";

// The drawing vocabulary every og.mp4 scene shares, so the videos read as the
// same brand as the PNG cards: the ground and red glows, the lockup, the
// App Store pill, the flame, avatars with the app's ring, and the motion
// (easing, count-ups, confetti, the loop fade).

export const W = VIDEO.width;
export const H = VIDEO.height;
export const T = VIDEO.seconds;

// ── Time ────────────────────────────────────────────────────────────────

export const clamp01 = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x);
export const lerp = (a: number, b: number, p: number) => a + (b - a) * p;
/** 0→1 progress of a beat that starts at `start` and lasts `dur` seconds. */
export const beat = (t: number, start: number, dur: number) =>
  clamp01((t - start) / dur);

export const ease = {
  outCubic: (p: number) => 1 - (1 - p) ** 3,
  outQuint: (p: number) => 1 - (1 - p) ** 5,
  inOutSine: (p: number) => -(Math.cos(Math.PI * p) - 1) / 2,
  inOutCubic: (p: number) =>
    p < 0.5 ? 4 * p * p * p : 1 - (-2 * p + 2) ** 3 / 2,
  /** A small overshoot, then settles: lands with life but no bounce. */
  outBack: (p: number) => {
    const c = 1.25;
    return 1 + (c + 1) * (p - 1) ** 3 + c * (p - 1) ** 2;
  },
};

/** Deterministic randomness, so every render of a link is the same video. */
export function seeded(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let x = Math.imul(a ^ (a >>> 15), 1 | a);
    x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x;
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

export function hashString(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++)
    h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

/**
 * The loop seam. Backgrounds (the ground's glows, a banner) loop on their
 * own; the FOREGROUND fades out over the last half-second, back to the
 * empty stage every scene's intro starts from, so a looping player never
 * cuts. Call after drawing the background: everything after it fades.
 */
export function foreground(g: Ctx, t: number) {
  g.globalAlpha = 1 - ease.inOutSine(beat(t, T - 0.45, 0.45));
}

// ── Ground ──────────────────────────────────────────────────────────────

export function radialGlow(
  g: Ctx,
  x: number,
  y: number,
  r: number,
  alpha: number,
  rgb = "199,37,84",
) {
  const grad = g.createRadialGradient(x, y, 0, x, y, r);
  grad.addColorStop(0, `rgba(${rgb},${alpha})`);
  grad.addColorStop(0.45, `rgba(${rgb},${alpha * 0.45})`);
  grad.addColorStop(1, `rgba(${rgb},0)`);
  g.fillStyle = grad;
  g.fillRect(x - r, y - r, r * 2, r * 2);
}

/** The site's ground with its two red glows, breathing and drifting. */
export function ground(g: Ctx, t: number) {
  g.fillStyle = BRAND.ground;
  g.fillRect(0, 0, W, H);
  const s = Math.sin((t / T) * Math.PI * 2);
  const c = Math.cos((t / T) * Math.PI * 2);
  radialGlow(g, 1050 + s * 40, 110 + c * 30, 470, 0.34);
  radialGlow(g, 40 - c * 30, 640 + s * 20, 330, 0.17);
}

// ── Shapes ──────────────────────────────────────────────────────────────

export function roundRect(
  g: Ctx,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number,
) {
  g.beginPath();
  g.roundRect(x, y, w, h, r);
}

/** Scale/rotate `draw` about (cx, cy) with an opacity — every pop-in. */
export function around(
  g: Ctx,
  cx: number,
  cy: number,
  opts: {
    scale?: number;
    rotate?: number;
    alpha?: number;
    dx?: number;
    dy?: number;
  },
  draw: () => void,
) {
  const { scale = 1, rotate = 0, alpha = 1, dx = 0, dy = 0 } = opts;
  if (alpha <= 0 || scale <= 0) return;
  g.save();
  g.globalAlpha *= alpha;
  g.translate(cx + dx, cy + dy);
  if (rotate) g.rotate(rotate);
  if (scale !== 1) g.scale(scale, scale);
  g.translate(-cx, -cy);
  draw();
  g.restore();
}

// ── Type ────────────────────────────────────────────────────────────────

export const font = {
  head: (px: number) => `${px}px "Bebas Neue"`,
  body: (px: number, weight: 500 | 700 = 500) => `${weight} ${px}px "DM Sans"`,
};

/** The largest size ≤ `max` at which `text` fits `width` (never below `min`). */
export function fitSize(
  g: Ctx,
  text: string,
  make: (px: number) => string,
  max: number,
  width: number,
  min = 24,
): number {
  let px = max;
  while (px > min) {
    g.font = make(px);
    if (g.measureText(text).width <= width) break;
    px -= 2;
  }
  return px;
}

/** Cut `text` with an ellipsis so it fits `width` in the current font. */
export function ellipsize(g: Ctx, text: string, width: number): string {
  if (g.measureText(text).width <= width) return text;
  let s = text;
  while (s.length > 1 && g.measureText(`${s}…`).width > width)
    s = s.slice(0, -1);
  return `${s.trimEnd()}…`;
}

/** Brand red→pink across a span. */
export function brandGradient(g: Ctx, x0: number, x1: number) {
  const grad = g.createLinearGradient(x0, 0, x1, 0);
  grad.addColorStop(0, BRAND.red);
  grad.addColorStop(1, BRAND.pink);
  return grad;
}

// ── Brand pieces ────────────────────────────────────────────────────────

/** Icon + wordmark (the cards' `Lockup`), sliding in from the left. */
export function lockup(
  g: Ctx,
  icon: Image,
  t: number,
  x = 72,
  y = 58,
  delay = 0.05,
) {
  const p = ease.outCubic(beat(t, delay, 0.6));
  around(g, x, y, { alpha: p, dx: (1 - p) * -24 }, () => {
    g.drawImage(icon, x, y, 58, 58);
    g.font = font.head(43);
    g.fillStyle = BRAND.ink;
    g.textBaseline = "alphabetic";
    g.fillText("MILE A DAY", x + 76, y + 45);
  });
}

const APPLE =
  "M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z";
const applePath = new Path2D(APPLE);

/**
 * The App Store pill every card closes on (`StoreLine`), popping in at
 * `start`; returns its width.
 */
export function storePill(
  g: Ctx,
  t: number,
  x: number,
  y: number,
  text = "Free on iPhone & Apple Watch",
  start = 1.2,
): number {
  g.font = font.body(25, 700);
  const w = 24 + 24 + 12 + g.measureText(text).width + 24;
  const h = 54;
  const p = beat(t, start, 0.55);
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
      g.save();
      g.translate(x + 22, y + 14);
      g.fillStyle = BRAND.ink;
      g.fill(applePath);
      g.restore();
      g.fillStyle = BRAND.ink;
      g.font = font.body(25, 700);
      g.textBaseline = "middle";
      g.fillText(text, x + 58, y + h / 2 + 1);
      g.textBaseline = "alphabetic";
    },
  );
  return w;
}

const FLAME =
  "M12 2c.6 3.2-1.1 5.1-2.6 6.8C7.9 10.4 6.5 12 6.5 14.6 6.5 18.2 9 21 12 21s5.5-2.8 5.5-6.4c0-2.3-1-4.1-2.2-5.6-.3 1.5-1 2.6-2.1 3.1.4-3.6-.4-7.3-1.2-10.1Z";
const flamePath = new Path2D(FLAME);

/** The streak flame, flickering (its 24-unit glyph scaled to `size`). */
export function flame(g: Ctx, x: number, y: number, size: number, t: number) {
  const flick = 1 + Math.sin(t * 17) * 0.035 + Math.sin(t * 29 + 1) * 0.025;
  g.save();
  g.translate(x + size / 2, y + size * 0.88);
  g.scale((size / 24) * (2 - flick), (size / 24) * flick);
  g.translate(-12, -21);
  const grad = g.createLinearGradient(0, 2, 0, 21);
  grad.addColorStop(0, "#ffd166");
  grad.addColorStop(0.55, "#fb923c");
  grad.addColorStop(1, "#ef4444");
  g.fillStyle = grad;
  g.fill(flamePath);
  g.restore();
}

/** "1,234" — the counters' format. */
export const count = (n: number) => Math.round(n).toLocaleString("en-US");

/**
 * A pill with the flame and "<n> day streak", counting up from `from` (half
 * the streak by default: never a "0 day streak", even for a frame) over
 * `dur` seconds starting at `start`. Returns its width.
 */
export function streakChip(
  g: Ctx,
  t: number,
  x: number,
  y: number,
  streak: number,
  opts: { start?: number; dur?: number; from?: number; px?: number; appear?: number } = {},
): number {
  const { start = 0.9, dur = 1.6, from = Math.floor(streak / 2), px = 30 } = opts;
  const p = beat(t, opts.appear ?? start - 0.2, 0.45);
  if (p <= 0) return 0;
  const n = lerp(from, streak, ease.outQuint(beat(t, start, dur)));
  // Width from the final number, so the pill doesn't grow as it counts.
  g.font = font.body(px, 700);
  const label = (v: number) => `${count(v)} day streak`;
  const w =
    px * 0.53 + px + 10 + g.measureText(label(streak)).width + px * 0.73;
  const h = px * 1.75;
  const landed = beat(t, start + dur * 0.55, 0.5);
  const pop = landed > 0 && landed < 1 ? Math.sin(landed * Math.PI) * 0.07 : 0;
  around(
    g,
    x + w / 2,
    y + h / 2,
    { scale: lerp(0.6, 1, ease.outBack(p)) + pop, alpha: clamp01(p * 2) },
    () => {
      roundRect(g, x, y, w, h, h / 2);
      g.fillStyle = "rgba(199,37,84,0.22)";
      g.fill();
      flame(g, x + px * 0.53, y + (h - px) / 2 - 1, px, t);
      g.fillStyle = BRAND.ink;
      g.textBaseline = "middle";
      g.font = font.body(px, 700);
      g.fillText(label(n), x + px * 0.53 + px + 10, y + h / 2 + 1);
      g.textBaseline = "alphabetic";
    },
  );
  return w;
}

/**
 * A round avatar (or initials) with the app's progress ring drawing round it.
 * `p` is the pop-in (0→1), `ring` the ring's sweep (0→1).
 */
export function avatar(
  g: Ctx,
  img: Image | null,
  initials: string,
  cx: number,
  cy: number,
  r: number,
  p: number,
  ring: number,
  t: number,
) {
  around(
    g,
    cx,
    cy,
    { scale: lerp(0.4, 1, ease.outBack(p)), alpha: clamp01(p * 2.5) },
    () => {
      // Halo behind the picture.
      radialGlow(g, cx, cy, r * 1.9, 0.34);
      g.save();
      g.beginPath();
      g.arc(cx, cy, r, 0, Math.PI * 2);
      g.clip();
      if (img) {
        const s = Math.max((r * 2) / img.width, (r * 2) / img.height);
        const w = img.width * s;
        const h = img.height * s;
        g.drawImage(img, cx - w / 2, cy - h / 2, w, h);
      } else {
        g.fillStyle = "#252525";
        g.fillRect(cx - r, cy - r, r * 2, r * 2);
        g.fillStyle = BRAND.ink;
        g.font = font.head(r * 0.9);
        g.textAlign = "center";
        g.textBaseline = "middle";
        g.fillText(initials, cx, cy + r * 0.06);
        g.textAlign = "left";
        g.textBaseline = "alphabetic";
      }
      g.restore();
      // The ring's track, then the sweep (from 12 o'clock, like the app).
      g.lineWidth = 8;
      g.strokeStyle = "rgba(199,37,84,0.25)";
      g.beginPath();
      g.arc(cx, cy, r + 10, 0, Math.PI * 2);
      g.stroke();
      if (ring > 0) {
        g.lineCap = "round";
        g.strokeStyle = brandGradient(g, cx - r, cx + r);
        g.beginPath();
        // A full 2π sweep with round caps draws nothing in Skia.
      g.arc(cx, cy, r + 10, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(ring, 0.9999));
        g.stroke();
        g.lineCap = "butt";
      }
    },
  );
}

// ── Celebration ─────────────────────────────────────────────────────────

// Brand colours plus white and the flame's gold: festive, still on-brand.
const CONFETTI = [BRAND.red, BRAND.pink, "#ffd166", "#f5f5f5"];

/** A small confetti burst from (x, y) at `start`, gone within ~1.4 s. */
export function confetti(
  g: Ctx,
  t: number,
  x: number,
  y: number,
  start: number,
  { n = 24, seed = 7, spread = 1 } = {},
) {
  const age = t - start;
  if (age < 0 || age > 1.4) return;
  const rand = seeded(seed);
  for (let i = 0; i < n; i++) {
    const angle = -Math.PI / 2 + (rand() - 0.5) * Math.PI * 1.25 * spread;
    const speed = 260 + rand() * 300;
    const vx = Math.cos(angle) * speed;
    const vy = Math.sin(angle) * speed;
    const drag = 1 - Math.exp(-age * 2.2);
    const px = x + (vx / 2.2) * drag;
    const py = y + (vy / 2.2) * drag + 170 * age * age;
    const spin = rand() * 10 + age * (6 + rand() * 8);
    const fade = 1 - beat(age, 0.75, 0.65);
    const w = 7 + rand() * 7;
    const h = 4 + rand() * 4;
    g.save();
    g.globalAlpha *= fade;
    g.translate(px, py);
    g.rotate(spin);
    g.scale(1, Math.cos(spin * 1.7));
    g.fillStyle = CONFETTI[i % CONFETTI.length];
    g.fillRect(-w / 2, -h / 2, w, h);
    g.restore();
  }
}

/** Greedy word wrap into at most `max` lines (the last one ellipsized). */
export function wrap(g: Ctx, text: string, width: number, max: number): string[] {
  const lines: string[] = [];
  let line = "";
  for (const word of text.split(/\s+/)) {
    const next = line ? `${line} ${word}` : word;
    if (g.measureText(next).width <= width || !line) line = next;
    else {
      lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  if (lines.length <= max) return lines;
  const kept = lines.slice(0, max);
  kept[max - 1] = ellipsize(g, lines.slice(max - 1).join(" "), width);
  return kept;
}
