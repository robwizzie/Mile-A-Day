// Composes a one-item look around the plain figure for each surface, the way
// FlameyOutfitLayer does: behind layers, then the plain figure image, then
// front layers; the trail tucked on tight surfaces, the companion scaled and
// placed beside him, held props by reach, the compact (widget) scale. Plus
// the motion kinds of docs/flamey-skins.md, as a function of time.
//
// app/FlameyExport/convert/match.mjs composes with THIS file (types stripped
// by Node) and diffs it against the Swift reference renders, so keep it
// erasable TypeScript and import only `./skinRender`.

import { drawLayer } from "./skinRender";
import type { DrawOptions, ImageMap, Recording } from "./skinRender";

/** FlameyArt's constants (app/FlameyExport/out/meta.json `constants`). match.mjs warns if they drift. */
export const CONSTANTS = {
  bopper_seat: 0.2,
  cape_tight_scale: 0.82,
  cape_tuck: 0.53,
  chest_top: 0.125,
  compact_threshold: 100,
  float_height: 0.5,
  ink: "#2A1410FF",
  leg_length: 0.15,
  leg_spread: 0.11,
  tight_art_bounds: [-0.49, 0.46],
  tight_mask_bounds: [-0.53, 0.5],
  tight_reach: 0.75,
  tight_top_bound: -0.72,
  trail_tuck: 0.56,
};

/** The plain look's anchors, body units (meta.json `plain.anchors_u`; face is above centre). */
export const ANCHORS = { top: -0.63, face: -0.03, bottom: 0.35, ground: 0.5, halfWidth: 0.41 };

export type SurfaceName = "card" | "tile" | "hero" | "widget";
export type Surface = { name: SurfaceName; label: string; reach: number; compact: boolean };
export const SURFACES: Surface[] = [
  { name: "card", label: "Card", reach: 0.9, compact: false },
  { name: "tile", label: "Tile", reach: 0.8, compact: false },
  { name: "hero", label: "Hero", reach: 0.62, compact: false },
  { name: "widget", label: "Widget", reach: 0.9, compact: true },
];

export const SLOTS = [
  "color", "head", "eyes", "chest", "back", "feet", "costume", "held", "trail", "companion", "aura", "bubble",
] as const;
export type Slot = (typeof SLOTS)[number];

export type Unlock = "always" | "plus" | { badge: string } | { month: number };

export type MotionSpec = {
  kind: "drift" | "bob" | "sway" | "wobble" | "pump" | "flutter" | "sweep" | "pulse" | "burst";
  period: number;
  dx?: number;
  dx_tight?: number;
  alpha?: number;
  dy?: number;
  deg?: number;
  back?: number;
  scale?: number;
};

export type Skin = {
  format: number;
  id: string;
  order: number;
  slot: Slot;
  name: string;
  family: string;
  unlock: Unlock;
  unlock_copy: string;
  holidays: string[];
  mood_prop: boolean;
  compact: boolean;
  rules: Record<string, unknown> & {
    hides?: string[];
    clashes?: string[];
    hover_lift?: number;
    floats?: boolean;
    is_cape?: boolean;
  };
  palette?: Record<string, unknown>;
  effects?: string[];
  art: Record<string, Recording>;
  pivots?: Record<string, [number, number]>;
  motion?: Record<string, MotionSpec>;
};

/** Splits "behind@reach=0.9,low=0" into its part and conditions. */
export function parseLayerKey(key: string): { part: string; cond: Record<string, string> } {
  const [part, rest] = key.split("@");
  const cond: Record<string, string> = {};
  if (rest) for (const kv of rest.split(",")) {
    const [k, v] = kv.split("=");
    cond[k] = v;
  }
  return { part, cond };
}

/**
 * The layer of `part` whose conditions match `want` (reach: nearest). A
 * layer without a condition matches any value of it, so a new skin with one
 * plain `behind` layer draws on every surface.
 */
export function pickLayer(
  art: Record<string, Recording>,
  part: string,
  want: Record<string, string | number> = {},
): { key: string; rec: Recording } | null {
  let best: { key: string; rec: Recording; score: number } | null = null;
  for (const [key, rec] of Object.entries(art)) {
    const p = parseLayerKey(key);
    if (p.part !== part) continue;
    let ok = true;
    let score = 0;
    for (const [k, v] of Object.entries(p.cond)) {
      if (k === "reach") {
        if (want.reach !== undefined) score += Math.abs(Number(v) - Number(want.reach));
        continue;
      }
      if (want[k] !== undefined && String(want[k]) !== v) ok = false;
    }
    if (!ok) continue;
    const more = best && Object.keys(p.cond).length > Object.keys(parseLayerKey(best.key).cond).length;
    if (!best || score < best.score || (score === best.score && more)) {
      best = { key, rec, score };
    }
  }
  return best ? { key: best.key, rec: best.rec } : null;
}

// ---------------------------------------------------------------- motion

/** One `repeatForever` ease-in-out autoreverse: 0 -> 1 over `period`, back over the next. */
export function phaseAt(t: number, period: number): number {
  if (!(period > 0)) return 0;
  const x = (t / period) % 2;
  const tri = x < 1 ? x : 2 - x;
  // SwiftUI .easeInOut is cubic-bezier(0.42, 0, 0.58, 1); solve x(s) = tri.
  let s = tri;
  for (let i = 0; i < 6; i++) {
    const bx = 3 * (1 - s) * (1 - s) * s * 0.42 + 3 * (1 - s) * s * s * 0.58 + s * s * s;
    const dx = 3 * (1 - s) * (1 - s) * 0.42 + 6 * (1 - s) * s * (0.58 - 0.42) + 3 * s * s * (1 - 0.58);
    if (Math.abs(dx) < 1e-6) break;
    s = Math.max(0, Math.min(1, s - (bx - tri) / dx));
  }
  return 3 * (1 - s) * s * s + s * s * s;
}

const lerp = (a: number, b: number, p: number) => a + (b - a) * p;

/**
 * Applies a layer's motion at phase p to ctx (body units) and returns the
 * opacity factor. `still` (a widget, Reduce Motion) draws the layer at rest.
 */
export function applyMotion(
  ctx: CanvasRenderingContext2D,
  m: MotionSpec | undefined,
  pivot: [number, number] | undefined,
  p: number,
  tight: boolean,
): number {
  if (!m) return 1;
  const [px, py] = pivot || [0, 0];
  const about = (fn: () => void) => {
    ctx.translate(px, py);
    fn();
    ctx.translate(-px, -py);
  };
  const rad = (deg: number) => (deg * Math.PI) / 180;
  switch (m.kind) {
    case "drift":
      ctx.translate(p * ((tight ? m.dx_tight : m.dx) ?? m.dx ?? 0), 0);
      return lerp(1, m.alpha ?? 1, p);
    case "bob":
      ctx.translate(0, p * (m.dy ?? 0));
      return 1;
    case "sway":
      about(() => ctx.rotate(rad(lerp(-(m.deg ?? 0), m.deg ?? 0, p))));
      return 1;
    case "wobble":
      about(() => ctx.rotate(rad(lerp(-(m.deg ?? 0) * (m.back ?? 0.35), m.deg ?? 0, p))));
      return 1;
    case "pump":
      ctx.translate(0, p * (m.dy ?? 0));
      about(() => ctx.scale(lerp(1, m.scale ?? 1, p), lerp(1, m.scale ?? 1, p)));
      return 1;
    case "flutter":
      about(() => ctx.scale(lerp(1.02, 0.9, p), lerp(0.98, 1.04, p)));
      return 1;
    case "sweep":
      about(() => ctx.rotate(rad(lerp(0, 150, p))));
      return 1;
    case "pulse":
      about(() => ctx.scale(lerp(0.9, 1.14, p), lerp(0.9, 1.14, p)));
      return lerp(1, 0.55, p);
    case "burst":
      about(() => ctx.scale(lerp(0.92, 1.1, p), lerp(0.92, 1.1, p)));
      return lerp(1, 0.8, p);
  }
  return 1;
}

// ---------------------------------------------------------------- compose

export type ComposeAssets = {
  /** The plain figure for this surface (768 px square, 1 unit = a third of it). */
  plain?: CanvasImageSource | null;
  /** Loaded `images` of every recording, by src key. */
  images?: ImageMap;
};

export type ComposeOptions = DrawOptions & {
  /** Seconds since start; null = still (every layer at rest). */
  time?: number | null;
  /** Draw the plain figure (false = art only). */
  figure?: boolean;
  /** Hard-edge tight mask like match.mjs (the app feathers it). */
  tightMask?: boolean;
};

const tightOf = (s: Surface) => s.reach < CONSTANTS.tight_reach;

/** Whether the skin draws anything on this surface (compact = widgets). */
export function drawsOn(skin: Skin, s: Surface): boolean {
  return !(s.compact && !skin.compact);
}

/**
 * Draws `skin` worn alone on surface `s` into the square [0, W] x [0, W]
 * of ctx (the 3-unit stage; Flamey's square is the middle third).
 */
export function composeLook(
  ctx: CanvasRenderingContext2D,
  W: number,
  skin: Skin,
  s: Surface,
  assets: ComposeAssets = {},
  opts: ComposeOptions = {},
): void {
  const U = W / 3;
  const C = CONSTANTS;
  const art = skin.art || {};
  const images = assets.images || {};
  const reach = s.reach;
  const tight = tightOf(s);
  const slot = skin.slot;
  const time = opts.time ?? null;
  const motion = skin.motion || {};
  const pivots = skin.pivots || {};
  const draws = drawsOn(skin, s);

  const phase = (base: string) => (time === null || !motion[base] ? 0 : phaseAt(time, motion[base].period));
  const moving = (base: string) => time !== null && !!motion[base];

  function body(fn: () => void) {
    ctx.save();
    ctx.translate(W / 2, W / 2);
    ctx.scale(U, U);
    if (s.compact) {
      ctx.translate(0, 0.5);
      ctx.scale(1 / (1 + C.leg_length), 1 / (1 + C.leg_length));
      ctx.translate(0, -0.5);
    }
    if (tight && opts.tightMask !== false) {
      // FlameyOutfitLayer's tight mask: a band as wide as his room (hard edge here).
      const [l, r] = C.tight_mask_bounds;
      ctx.beginPath();
      ctx.rect(l, -5, r - l, 10);
      ctx.clip();
    }
    fn();
    ctx.restore();
  }

  /** Draws a layer with its motion (keyed by the layer's base part). */
  function layer(part: string, want: Record<string, string | number>, base = part, extra?: () => number) {
    const hit = pickLayer(art, part, { reach, ...want });
    if (!hit) return;
    ctx.save();
    let alpha = extra ? extra() : 1;
    if (moving(base)) alpha *= applyMotion(ctx, motion[base], pivots[hit.key] ?? pivots[base], phase(base), tight);
    drawLayer(ctx, hit.rec, { ...opts, alpha: (opts.alpha ?? 1) * alpha }, images);
    ctx.restore();
  }

  // Behind.
  if (draws) body(() => {
    if (slot === "trail") {
      ctx.save();
      if (tight) ctx.scale(C.trail_tuck, 1);
      layer("behind", { low: 0 });
      ctx.restore();
    } else if (slot === "back") {
      layer("behind", { glow: 1 });
    } else {
      layer("behind", {});
    }
  });

  // A hovering look (rocket boots, winged sandals) lifts the whole figure.
  const hover = slot === "feet" && !s.compact ? Number(skin.rules?.hover_lift || 0) : 0;
  if (opts.figure !== false && assets.plain) ctx.drawImage(assets.plain, 0, -hover * U, W, W);

  if (!draws) return;
  // Front.
  body(() => {
    layer("front", slot === "feet" ? { jets: s.compact ? 0 : 1 } : {});
    layer("crown", {});
    layer("bopper-band", {});
    layer("bopper-springs", {});

    // Held: the whole prop wobbles (or pumps) about his fist; the accent
    // moves about its own pivot on top of that.
    if (pickLayer(art, "held-body", { reach }) || pickLayer(art, "held-accent", { reach })) {
      ctx.save();
      const bodyHit = pickLayer(art, "held-body", { reach });
      if (moving("held-body")) applyMotion(ctx, motion["held-body"], (bodyHit && pivots[bodyHit.key]) || pivots["held-body"], phase("held-body"), tight);
      if (bodyHit) drawLayer(ctx, bodyHit.rec, opts, images);
      const acc = pickLayer(art, "held-accent", { reach });
      if (acc) {
        ctx.save();
        let a = 1;
        if (moving("held-accent")) a = applyMotion(ctx, motion["held-accent"], pivots[acc.key] || pivots["held-accent"], phase("held-accent"), tight);
        drawLayer(ctx, acc.rec, { ...opts, alpha: (opts.alpha ?? 1) * a }, images);
        ctx.restore();
      }
      ctx.restore();
    }

    if (pickLayer(art, "companion-body", { pose: "rest" })) {
      const floats = !!skin.rules?.floats;
      const k = tight ? 0.6 : 1.15;
      const x = tight ? (floats ? 0.3 : 0.26) : Math.max(0.56, Math.min(0.7, reach - 0.14));
      const lift = tight && floats ? -0.42 : 0;
      const g = ANCHORS.ground;
      const place = (dy: number, part: string, want: Record<string, string | number>, bob: boolean) => {
        const hit = pickLayer(art, part, want);
        if (!hit) return;
        ctx.save();
        ctx.translate(x, dy);
        // The bob is in screen points (outside the companion's scale).
        if (bob && moving("companion-body")) applyMotion(ctx, motion["companion-body"], undefined, phase("companion-body"), tight);
        ctx.translate(0, g);
        ctx.scale(k, k);
        ctx.translate(0, -g);
        drawLayer(ctx, hit.rec, opts, images);
        ctx.restore();
      };
      if (!(tight && floats)) place(0, "companion-shadow", {}, false);
      place(lift, "companion-body", { pose: "rest" }, true);
    }
  });
}

/** Loads every recording's embedded images (data URLs) for drawImage. */
export async function loadSkinImages(skin: Skin): Promise<ImageMap> {
  const out: ImageMap = {};
  const jobs: Promise<void>[] = [];
  for (const rec of Object.values(skin.art || {})) {
    for (const [k, src] of Object.entries(rec.images || {})) {
      jobs.push(
        new Promise<void>((ok) => {
          const img = new Image();
          img.onload = () => {
            out[k] = img;
            ok();
          };
          img.onerror = () => ok();
          img.src = src;
        }),
      );
    }
  }
  await Promise.all(jobs);
  return out;
}

/** The colour slot's palette as token -> colour (for `tok` paints). */
export function paletteTokens(palette: Record<string, unknown> | undefined): Record<string, string> | null {
  if (!palette) return null;
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(palette)) {
    if (typeof v === "string" && v.startsWith("#")) out[k] = v;
    else if (Array.isArray(v)) v.forEach((c, i) => typeof c === "string" && c.startsWith("#") && (out[`${k}.${i}`] = c));
  }
  return out;
}
