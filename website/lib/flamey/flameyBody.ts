// Flamey's body, drawn from code the way the app draws it, so a colour skin
// shows in its own colours instead of the plain image's. A port of
// FlameBuddyFigure (app/MileADayWidgets/FlameBuddyFigure.swift): the healthy,
// still figure standing on his legs (FlameBuddyFigure.mascotLegLength) with
// his arms at rest (FlameArmPose.rest), which is what the plain-*.png images
// are. Palette effects come from ./paletteFx (FlameyPalettes.swift).
//
// Coordinates: Flamey's square is [-0.5, 0.5]² with y down (SwiftUI's
// `size` = 1, origin at the figure frame's centre), the same body units
// compose.ts draws layers in.
//
// Erasable TypeScript, relative imports only (see compose.ts).

import { drawBodyFx, drawInnerFx } from "./paletteFx";
import type { PaletteJson } from "./paletteFx";

export type { PaletteJson };

type RGBA = [number, number, number, number];

/** "#RRGGBBAA" | "#RRGGBB" → [r, g, b, a] (0–255, a 0–1). */
function hex(c: string): RGBA {
  const h = c.replace("#", "");
  const n = (i: number) => parseInt(h.slice(i, i + 2), 16);
  return [n(0), n(2), n(4), h.length >= 8 ? n(6) / 255 : 1];
}
const css = (c: RGBA, o = 1) =>
  `rgba(${c[0]},${c[1]},${c[2]},${+(c[3] * o).toFixed(4)})`;
const rgb = (r: number, g: number, b: number, a = 1): RGBA => [
  r * 255,
  g * 255,
  b * 255,
  a,
];

// FlameBuddyFigure's healthy look (no wardrobe palette). SwiftUI's .orange
// and .yellow are (1, 0.584, 0) and (1, 0.8, 0).
const HEALTHY = {
  outer: [rgb(1, 0.95, 0.32), rgb(1, 0.584, 0), rgb(1, 0.22, 0.1)],
  inner: [rgb(1, 0.98, 0.44), rgb(1, 0.65, 0.12)],
  innerOpacity: 0.82,
  glow: rgb(1, 0.584, 0),
  core: rgb(1, 0.8, 0),
  eye: rgb(0.2, 0.07, 0.04),
  rim: rgb(1, 1, 1, 0.28),
  armRim: rgb(1, 1, 1, 0.3),
};
const GLOW_OPACITY = 0.48; // FlameHealth.healthy.glowOpacity
const LEG = 0.15; // FlameBuddyFigure.mascotLegLength
const LIFT = LEG; // resolvedLift: legs × bodyScale (1 when healthy)
const MOUTH = rgb(0.24, 0.04, 0.04);
const TONGUE = rgb(1, 0.42, 0.34);

type Pt = [number, number];

/** FlameBuddyOuterShape in a w×h frame at (x0, y0), still (wobble 0). */
function outerPath(
  ctx: CanvasRenderingContext2D,
  x0: number,
  y0: number,
  w: number,
  h: number,
) {
  const X = (v: number) => x0 + v * w;
  const Y = (v: number) => y0 + v * h;
  ctx.beginPath();
  ctx.moveTo(X(0.5), Y(0.02));
  ctx.bezierCurveTo(X(0.35), Y(0.13), X(0.27), Y(0.25), X(0.28), Y(0.42));
  ctx.bezierCurveTo(X(0.2), Y(0.36), X(0.15), Y(0.46), X(0.18), Y(0.56));
  ctx.bezierCurveTo(X(0.12), Y(0.61), X(0.08), Y(0.66), X(0.08), Y(0.72));
  ctx.bezierCurveTo(X(0.08), Y(0.9), X(0.24), Y(0.98), X(0.5), Y(0.98));
  ctx.bezierCurveTo(X(0.76), Y(0.98), X(0.92), Y(0.9), X(0.92), Y(0.72));
  ctx.bezierCurveTo(X(0.92), Y(0.55), X(0.75), Y(0.48), X(0.69), Y(0.35));
  ctx.bezierCurveTo(X(0.78), Y(0.2), X(0.62), Y(0.11), X(0.5), Y(0.02));
  ctx.closePath();
}

/** FlameBuddyInnerShape, still. */
function innerPath(
  ctx: CanvasRenderingContext2D,
  x0: number,
  y0: number,
  w: number,
  h: number,
) {
  const X = (v: number) => x0 + v * w;
  const Y = (v: number) => y0 + v * h;
  ctx.beginPath();
  ctx.moveTo(X(0.52), Y(0.02));
  ctx.bezierCurveTo(X(0.35), Y(0.2), X(0.37), Y(0.34), X(0.32), Y(0.48));
  ctx.bezierCurveTo(X(0.22), Y(0.54), X(0.18), Y(0.62), X(0.18), Y(0.72));
  ctx.bezierCurveTo(X(0.18), Y(0.9), X(0.34), Y(0.98), X(0.5), Y(0.98));
  ctx.bezierCurveTo(X(0.66), Y(0.98), X(0.82), Y(0.9), X(0.82), Y(0.72));
  ctx.bezierCurveTo(X(0.82), Y(0.56), X(0.62), Y(0.52), X(0.6), Y(0.38));
  ctx.bezierCurveTo(X(0.72), Y(0.24), X(0.6), Y(0.14), X(0.52), Y(0.02));
  ctx.closePath();
}

/** FlameBuddySmileShape in a rect. */
function smilePath(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
) {
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.quadraticCurveTo(x + w / 2, y + h * 0.62, x + w, y);
  ctx.bezierCurveTo(
    x + w - w * 0.06,
    y + h + h * 0.34,
    x + w * 0.06,
    y + h + h * 0.34,
    x,
    y,
  );
  ctx.closePath();
}

/** A SwiftUI LinearGradient (evenly spaced stops) between two points. */
function linear(
  ctx: CanvasRenderingContext2D,
  a: Pt,
  b: Pt,
  colors: RGBA[],
  o = 1,
) {
  const g = ctx.createLinearGradient(a[0], a[1], b[0], b[1]);
  const n = colors.length;
  colors.forEach((c, i) =>
    g.addColorStop(n === 1 ? 0 : i / (n - 1), css(c, o)),
  );
  return g;
}

/** Blur that scales with the canvas (ctx units → device px). */
function blurPx(ctx: CanvasRenderingContext2D, r: number) {
  const m = ctx.getTransform();
  return r * Math.hypot(m.a, m.b);
}

/** Point on a quadratic Bézier, and the sub-curve from t0 to 1 (for `trimmedPath`). */
function quadAt(p0: Pt, c: Pt, p1: Pt, t: number): Pt {
  const u = 1 - t;
  return [
    u * u * p0[0] + 2 * u * t * c[0] + t * t * p1[0],
    u * u * p0[1] + 2 * u * t * c[1] + t * t * p1[1],
  ];
}
function quadFrom(p0: Pt, c: Pt, p1: Pt, t: number): [Pt, Pt, Pt] {
  const start = quadAt(p0, c, p1, t);
  const c2: Pt = [c[0] + (p1[0] - c[0]) * t, c[1] + (p1[1] - c[1]) * t];
  return [start, c2, p1];
}

export type BodyOptions = {
  /** The colour skin's `palette`; omitted = his plain healthy colours. */
  palette?: PaletteJson | null;
};

/** Draws the whole figure (glow, shadow, legs, body, face, arms) into [-0.5, 0.5]². */
export function drawFlameyBody(
  ctx: CanvasRenderingContext2D,
  opts: BodyOptions = {},
): void {
  const p = opts.palette || null;
  const outer = p?.outer?.length ? p.outer.map(hex) : HEALTHY.outer;
  const inner = p?.inner?.length ? p.inner.map(hex) : HEALTHY.inner;
  const glow = p?.glow ? hex(p.glow) : HEALTHY.glow;
  const core = p?.core ? hex(p.core) : HEALTHY.core;
  const eye = p?.eye ? hex(p.eye) : HEALTHY.eye;
  const rim = p?.rim ? hex(p.rim) : HEALTHY.rim;
  const armRim = p?.rim ? hex(p.rim) : HEALTHY.armRim;
  const bodyOpacity = p?.bodyOpacity ?? 1;
  const innerOpacity = p?.innerOpacity ?? HEALTHY.innerOpacity;
  const upper = outer[Math.max(0, outer.length - 2)];
  const lower = outer[outer.length - 1];

  ctx.save();

  // ---- glowLayer (centred on the figure frame; not lifted)
  ctx.save();
  ctx.filter = `blur(${blurPx(ctx, 0.18)}px)`;
  ctx.fillStyle = css(glow, GLOW_OPACITY * 0.45);
  ctx.beginPath();
  ctx.arc(0, 0, 0.46, 0, Math.PI * 2); // Circle in a 1.1×0.92 frame: d = 0.92
  ctx.fill();
  ctx.filter = `blur(${blurPx(ctx, 0.09)}px)`;
  ctx.fillStyle = css(core, 0.16);
  ctx.beginPath();
  ctx.arc(0, 0.12, 0.31, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  // ---- FlameyRender.glowBehind: the legendary colours' halo and orbiting
  // embers, centred half a unit above his base (anchors.bottom 0.35).
  const fx = p?.effects ?? [];
  if (fx.includes("halo") || fx.includes("embers")) {
    ctx.save();
    ctx.translate(0, 0.35 - 0.5);
    if (fx.includes("halo")) {
      const disc = ctx.createRadialGradient(0, 0, 0.22, 0, 0, 0.64);
      disc.addColorStop(0, css(glow, 0.4));
      disc.addColorStop(1, css(glow, 0));
      ctx.fillStyle = disc;
      ctx.beginPath();
      ctx.arc(0, 0, 0.725, 0, Math.PI * 2);
      ctx.fill();
      const ring = ctx.createConicGradient(0, 0, 0);
      const stops = [css(glow, 0.7), "rgba(255,255,255,0.75)", css(glow, 0.15), "rgba(255,255,255,0.85)", css(glow, 0.7)];
      stops.forEach((c, i) => ring.addColorStop(i / (stops.length - 1), c));
      ctx.strokeStyle = ring;
      ctx.lineWidth = 0.012;
      ctx.beginPath();
      ctx.arc(0, 0, 0.55 - 0.006, 0, Math.PI * 2); // strokeBorder: inside the 1.10 circle
      ctx.stroke();
    }
    if (fx.includes("embers")) {
      for (let i = 0; i < 7; i++) {
        const r = 0.03 - 0.003 * (i % 3);
        const a = (i / 7) * 2 * Math.PI;
        const x = Math.cos(a) * 0.62;
        const y = Math.sin(a) * 0.2;
        const g = ctx.createRadialGradient(x, y, 0, x, y, r * 1.6);
        g.addColorStop(0, "#ffffff");
        g.addColorStop(0.5, css(glow));
        g.addColorStop(1, css(glow, 0));
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(x, y, r * 1.6, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.restore();
  }

  // ---- groundLayer: a soft shadow at his feet
  ctx.save();
  ctx.filter = `blur(${blurPx(ctx, 0.012)}px)`;
  ctx.fillStyle = "rgba(0,0,0,0.24)";
  ctx.beginPath();
  ctx.ellipse(0, 0.44, 0.39, 0.08, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  // ---- legsLayer
  ctx.save();
  ctx.globalAlpha *= bodyOpacity;
  {
    const bottom = 0.5 - LIFT;
    const top = bottom - 0.1;
    const ankle = bottom + LEG - 0.06;
    const thick = 0.1;
    const spread = 0.11;
    const rimW = 0.012;
    for (const side of [-1, 1]) {
      const hip: Pt = [side * (spread - 0.025), top];
      const foot: Pt = [side * spread, ankle];
      const knee: Pt = [side * (spread + 0.02), (top + ankle) / 2];
      const tx = foot[0] - 0.062 + side * 0.022;
      const ty = ankle - 0.012;
      const tw = 0.124;
      const th = 0.066;
      ctx.fillStyle = css(rim);
      ctx.beginPath();
      ctx.ellipse(
        tx + tw / 2,
        ty + th / 2,
        tw / 2 + rimW,
        th / 2 + rimW,
        0,
        0,
        Math.PI * 2,
      );
      ctx.fill();
      ctx.fillStyle = linear(ctx, [0, ty], [0, ty + th], [upper, lower]);
      ctx.beginPath();
      ctx.ellipse(tx + tw / 2, ty + th / 2, tw / 2, th / 2, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = "rgba(255,255,255,0.28)";
      ctx.beginPath();
      ctx.ellipse(
        tx + tw * 0.22 + (tw * 0.34) / 2,
        ty + th * 0.14 + (th * 0.3) / 2,
        (tw * 0.34) / 2,
        (th * 0.3) / 2,
        0,
        0,
        Math.PI * 2,
      );
      ctx.fill();

      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(hip[0], hip[1]);
      ctx.quadraticCurveTo(knee[0], knee[1], foot[0], foot[1]);
      ctx.strokeStyle = css(rim);
      ctx.lineWidth = thick + rimW * 2;
      ctx.stroke();
      ctx.strokeStyle = linear(ctx, [0, top], [0, ankle], [upper, lower]);
      ctx.lineWidth = thick;
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(knee[0] - thick * 0.28 - side * thick * 0.08, bottom + 0.02);
      ctx.lineTo(foot[0] - thick * 0.26, foot[1] - thick * 0.2);
      ctx.strokeStyle = "rgba(255,255,255,0.32)";
      ctx.lineWidth = thick * 0.18;
      ctx.stroke();
    }
  }
  ctx.restore();

  // ---- the body: a 0.82 × 1 frame centred on the figure, lifted onto his legs
  const bx = -0.41;
  const by = -0.5 - LIFT;
  const bw = 0.82;
  const bh = 1;
  ctx.save();
  ctx.globalAlpha *= bodyOpacity;

  // Outer flame, with its glow as a shadow.
  let outerFill: CanvasGradient;
  if (p?.angular) {
    const g = ctx.createConicGradient(0, bx + 0.5 * bw, by + 0.66 * bh);
    const cs = [...outer, outer[0]];
    cs.forEach((c, i) => g.addColorStop(i / (cs.length - 1), css(c)));
    outerFill = g;
  } else {
    const s = p?.start ?? [0.5, 0];
    const e = p?.end ?? [0.5, 1];
    outerFill = linear(
      ctx,
      [bx + s[0] * bw, by + s[1] * bh],
      [bx + e[0] * bw, by + e[1] * bh],
      outer,
    );
  }
  ctx.save();
  ctx.shadowColor = css(glow, GLOW_OPACITY);
  ctx.shadowBlur = blurPx(ctx, 0.16) * 2;
  outerPath(ctx, bx, by, bw, bh);
  ctx.fillStyle = outerFill;
  ctx.fill();
  ctx.restore();
  if (p?.effects?.length) {
    ctx.save();
    outerPath(ctx, bx, by, bw, bh);
    ctx.clip();
    ctx.translate(bx, by);
    drawBodyFx(ctx, p, bw, bh, 1);
    ctx.restore();
  }
  outerPath(ctx, bx, by, bw, bh);
  ctx.strokeStyle = css(rim);
  ctx.lineWidth = 0.012;
  ctx.stroke();

  // Inner flame: 0.54 × 0.58, centred, 0.13 down.
  const iw = 0.54;
  const ih = 0.58;
  const ix = -iw / 2;
  const iy = by + bh / 2 + 0.13 - ih / 2;
  ctx.save();
  ctx.globalAlpha *= innerOpacity;
  innerPath(ctx, ix, iy, iw, ih);
  ctx.fillStyle = linear(ctx, [0, iy], [0, iy + ih], inner);
  ctx.fill();
  if (p?.effects?.length) {
    innerPath(ctx, ix, iy, iw, ih);
    ctx.clip();
    ctx.translate(ix, iy);
    drawInnerFx(ctx, p, iw, ih, 1);
  }
  ctx.restore();

  // Face, 0.18 below the body's centre: two eyes 0.17 apart, the grin 0.13 lower.
  const fy = by + bh / 2 + 0.18;
  for (const side of [-1, 1]) {
    const ex = side * (0.085 + 0.06);
    ctx.fillStyle = css(eye);
    ctx.beginPath();
    ctx.ellipse(ex, fy, 0.06, 0.155 / 2, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "rgba(255,255,255,0.92)";
    ctx.beginPath();
    ctx.arc(
      ex - 0.06 + 0.024 + 0.0175,
      fy - 0.0775 + 0.03 + 0.0175,
      0.0175,
      0,
      Math.PI * 2,
    );
    ctx.fill();
  }
  const mx = -0.135;
  const my = fy + 0.13 - 0.115 / 2;
  ctx.save();
  smilePath(ctx, mx, my, 0.27, 0.115);
  ctx.fillStyle = css(MOUTH);
  ctx.fill();
  ctx.clip();
  ctx.fillStyle = css(TONGUE);
  ctx.beginPath();
  ctx.roundRect(-0.055, my + 0.115 - 0.045, 0.11, 0.045, 0.0225);
  ctx.fill();
  ctx.restore();

  ctx.restore(); // body

  // ---- arms (FlameBuddyArms, rest pose, still: 30° out, less the 2° sway)
  ctx.save();
  ctx.globalAlpha *= bodyOpacity;
  {
    const L = 0.145;
    const thick = 0.098;
    const r = 0.056;
    const rimW = 0.011;
    for (const side of [-1, 1]) {
      ctx.save();
      ctx.translate(side * 0.285, 0.5 - LIFT - 0.27);
      ctx.rotate(((-side * 30 + side * 2) * Math.PI) / 180);
      const o: Pt = [0, 0];
      const end: Pt = [0, L];
      const bend = -side * thick * 0.35;
      const c: Pt = [bend, L * 0.5];
      ctx.lineCap = "round";
      // The rim only where the arm is clear of his body (trim 0.38 → 1).
      const [s0, c0, e0] = quadFrom(o, c, end, 0.38);
      ctx.beginPath();
      ctx.moveTo(s0[0], s0[1]);
      ctx.quadraticCurveTo(c0[0], c0[1], e0[0], e0[1]);
      ctx.strokeStyle = css(armRim);
      ctx.lineWidth = thick + rimW * 2;
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(o[0], o[1]);
      ctx.quadraticCurveTo(c[0], c[1], end[0], end[1]);
      ctx.strokeStyle = linear(ctx, o, end, [upper, lower]);
      ctx.lineWidth = thick;
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(-thick * 0.22, thick * 0.2);
      ctx.quadraticCurveTo(
        bend - thick * 0.22,
        L * 0.5,
        end[0] - thick * 0.22,
        end[1] - thick * 0.3,
      );
      ctx.strokeStyle = "rgba(255,255,255,0.26)";
      ctx.lineWidth = thick * 0.16;
      ctx.stroke();
      // A round mitten with a thumb.
      ctx.fillStyle = css(armRim);
      ctx.beginPath();
      ctx.arc(end[0], end[1], r, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = css(upper);
      ctx.beginPath();
      ctx.arc(end[0], end[1], r - rimW, 0, Math.PI * 2);
      ctx.fill();
      const hg = ctx.createRadialGradient(
        end[0] - r * 0.35,
        end[1] - r * 0.35,
        0,
        end[0] - r * 0.35,
        end[1] - r * 0.35,
        r * 1.1,
      );
      hg.addColorStop(0, "rgba(255,255,255,0.5)");
      hg.addColorStop(1, "rgba(255,255,255,0)");
      ctx.fillStyle = hg;
      ctx.fill();
      ctx.beginPath();
      // SwiftUI's addArc `clockwise` is inverted in y-down space.
      const a0 = ((side > 0 ? 200 : -20) * Math.PI) / 180;
      const a1 = ((side > 0 ? 290 : -110) * Math.PI) / 180;
      ctx.arc(
        end[0] + side * r * 0.1,
        end[1] - r * 0.05,
        r * 0.55,
        a0,
        a1,
        side < 0,
      );
      ctx.strokeStyle = "rgba(0,0,0,0.22)";
      ctx.lineWidth = r * 0.16;
      ctx.stroke();
      ctx.restore();
    }
  }
  ctx.restore();

  ctx.restore();
}
