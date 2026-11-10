// Flamey's colour-palette effects on a 2D canvas: a port of
// app/MileADayWidgets/FlameyPalettes.swift (`FlameyPaletteBodyFX`,
// `FlameyPaletteInnerFX`, `FlameyMonthlyFX`) and `FlameyArt.star`.
//
// Loaded by Node's `stripTypeScriptTypes` too: keep this ERASABLE TypeScript
// (no enums / namespaces / parameter properties / decorators) and import-free.
//
// Frames, as FlameBuddyFigure lays them out:
// - BODY fx are an `.overlay` on `FlameBuddyOuterShape`, so they share the outer
//   shape's frame (size*0.82 x size). Swift CLIPS them itself: the Canvas calls
//   `ctx.clip(to: FlameBuddyOuterShape.path)` and Prism's gradient is
//   `.mask`ed to the same shape. `drawBodyFx` does the same clip (wobble 0), so
//   an extra caller clip is harmless.
// - INNER fx overlay `FlameBuddyInnerShape`, framed size*0.54 x size*0.58 and
//   offset y by size*0.13 from the body's centre. Swift fills the inner shape
//   (so it is clipped to it); `drawInnerFx` clips to it too.
// - `bodyOpacity` / `innerOpacity` are applied by the figure to the whole layer
//   (fill + fx); they are the caller's job, not drawn here.
// - `halo` and `embers` live OUTSIDE the silhouette (FlameyRender.swift) and are
//   not drawn here.
//
// SwiftUI -> canvas notes:
// - Angles: both measure from +x towards +y (y-down). SwiftUI's
//   `addArc(clockwise: false)` sweeps increasing angles, i.e. visually
//   clockwise on screen == canvas `arc(..., anticlockwise = false)`.
// - `GraphicsContext.rotate(by:)` turns about the canvas origin, positive =
//   visually clockwise == `ctx.rotate`.
// - `.blur(radius: r)` -> `ctx.filter = blur(rpx)` 1:1 (SwiftUI's radius is
//   close to, not exactly, the CSS std-dev). Needs `ctx.filter` (no-op in
//   Safari < 18: blurred layers then draw sharp).
// - Still frame: Prism's colour cycle is drawn at rotation 0 (its rest state,
//   which is also what an ImageRenderer still shows).

export type PaletteJson = {
  outer?: string[];
  inner?: string[];
  core?: string;
  glow?: string;
  eye?: string;
  rim?: string;
  effects?: string[];
  angular?: boolean;
  bodyOpacity?: number;
  innerOpacity?: number | null;
  start?: [number, number];
  end?: [number, number];
};

type Ctx = CanvasRenderingContext2D;

/** Raw names of `FlameyPaletteEffect` (Swift case names). */
export const PALETTE_EFFECTS = [
  "sheen",
  "stars",
  "denseStars",
  "lava",
  "ribbons",
  "candy",
  "waves",
  "nebula",
  "hotCore",
  "prismCycle",
  "halo",
  "embers",
  "snowflakes",
  "hearts",
  "clovers",
  "raindrops",
  "rainbow",
  "flowers",
  "sunRays",
  "flagStripes",
  "melon",
  "leaves",
  "pumpkinRibs",
  "knit",
  "stringLights",
];

const MONTHLY = [
  "snowflakes",
  "hearts",
  "clovers",
  "raindrops",
  "rainbow",
  "flowers",
  "sunRays",
  "flagStripes",
  "melon",
  "leaves",
  "pumpkinRibs",
  "knit",
  "stringLights",
];
const DRAWN_HERE = [
  "sheen",
  "stars",
  "denseStars",
  "lava",
  "ribbons",
  "candy",
  "waves",
  "nebula",
].concat(MONTHLY);

const RAD = Math.PI / 180;
const TAU = Math.PI * 2;

/** `FlameyPalette.hex(v, o)` as a CSS colour. */
function hx(v: number, o = 1): string {
  return `rgba(${(v >> 16) & 0xff},${(v >> 8) & 0xff},${v & 0xff},${o})`;
}
const white = (o = 1) => hx(0xffffff, o);

/** "#RRGGBBAA" / "#RRGGBB" (skin files) -> CSS colour. */
function cssColor(s: string): string {
  const m = /^#?([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(s.trim());
  if (!m) return s;
  const v = parseInt(m[1], 16);
  const a = m[2] === undefined ? 1 : parseInt(m[2], 16) / 255;
  return hx(v, a);
}

function effectSet(p: PaletteJson): Set<string> {
  const known = new Set(PALETTE_EFFECTS);
  return new Set((p.effects ?? []).filter((e) => known.has(e)));
}
const hasAny = (fx: Set<string>, names: string[]) =>
  names.some((n) => fx.has(n));

// MARK: - Shapes (trace into the current path; caller begins/fills)

/** `FlameBuddyOuterShape(wobble:)` in (0,0)-(w,h). */
export function traceOuterShape(
  ctx: Ctx,
  w: number,
  h: number,
  wobble = 0,
): void {
  const x = (v: number) => v * w,
    y = (v: number) => v * h;
  ctx.moveTo(x(0.5 + wobble * 0.1), y(0.02));
  ctx.bezierCurveTo(
    x(0.35 + wobble),
    y(0.13),
    x(0.27 - wobble * 0.3),
    y(0.25),
    x(0.28 + wobble * 0.35),
    y(0.42),
  );
  ctx.bezierCurveTo(
    x(0.2),
    y(0.36),
    x(0.15),
    y(0.46),
    x(0.18 - wobble * 0.2),
    y(0.56),
  );
  ctx.bezierCurveTo(x(0.12), y(0.61), x(0.08), y(0.66), x(0.08), y(0.72));
  ctx.bezierCurveTo(x(0.08), y(0.9), x(0.24), y(0.98), x(0.5), y(0.98));
  ctx.bezierCurveTo(x(0.76), y(0.98), x(0.92), y(0.9), x(0.92), y(0.72));
  ctx.bezierCurveTo(
    x(0.92),
    y(0.55),
    x(0.75 + wobble),
    y(0.48),
    x(0.69 + wobble * 0.25),
    y(0.35),
  );
  ctx.bezierCurveTo(
    x(0.78),
    y(0.2),
    x(0.62),
    y(0.11),
    x(0.5 + wobble * 0.1),
    y(0.02),
  );
  ctx.closePath();
}

/** `FlameBuddyInnerShape(wobble:)` in (0,0)-(w,h). */
export function traceInnerShape(
  ctx: Ctx,
  w: number,
  h: number,
  wobble = 0,
): void {
  const x = (v: number) => v * w,
    y = (v: number) => v * h;
  ctx.moveTo(x(0.52 + wobble * 0.2), y(0.02));
  ctx.bezierCurveTo(x(0.35), y(0.2), x(0.37), y(0.34), x(0.32), y(0.48));
  ctx.bezierCurveTo(x(0.22), y(0.54), x(0.18), y(0.62), x(0.18), y(0.72));
  ctx.bezierCurveTo(x(0.18), y(0.9), x(0.34), y(0.98), x(0.5), y(0.98));
  ctx.bezierCurveTo(x(0.66), y(0.98), x(0.82), y(0.9), x(0.82), y(0.72));
  ctx.bezierCurveTo(
    x(0.82),
    y(0.56),
    x(0.62),
    y(0.52),
    x(0.6 + wobble * 0.22),
    y(0.38),
  );
  ctx.bezierCurveTo(
    x(0.72),
    y(0.24),
    x(0.6),
    y(0.14),
    x(0.52 + wobble * 0.2),
    y(0.02),
  );
  ctx.closePath();
}

/** `Path(ellipseIn: CGRect(x, y, w, h))`. */
function ellipseIn(ctx: Ctx, x: number, y: number, w: number, h: number): void {
  ctx.moveTo(x + w, y + h / 2);
  ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, TAU);
}

function fillEllipse(
  ctx: Ctx,
  x: number,
  y: number,
  w: number,
  h: number,
  style: string | CanvasGradient,
): void {
  ctx.beginPath();
  ellipseIn(ctx, x, y, w, h);
  ctx.fillStyle = style;
  ctx.fill();
}

function fillRect(
  ctx: Ctx,
  x: number,
  y: number,
  w: number,
  h: number,
  style: string,
): void {
  ctx.fillStyle = style;
  ctx.fillRect(x, y, w, h);
}

/** `FlameyArt.star`. */
function star(
  ctx: Ctx,
  cx: number,
  cy: number,
  r: number,
  inner = 0.45,
  points = 5,
): void {
  for (let i = 0; i < points * 2; i++) {
    const rr = i % 2 === 1 ? r * inner : r;
    const a = -Math.PI / 2 + (i * Math.PI) / points;
    const qx = cx + rr * Math.cos(a),
      qy = cy + rr * Math.sin(a);
    if (i === 0) ctx.moveTo(qx, qy);
    else ctx.lineTo(qx, qy);
  }
  ctx.closePath();
}

function fillStar(
  ctx: Ctx,
  cx: number,
  cy: number,
  r: number,
  inner: number,
  style: string,
): void {
  ctx.beginPath();
  star(ctx, cx, cy, r, inner);
  ctx.fillStyle = style;
  ctx.fill();
}

function heart(ctx: Ctx, x: number, y: number, r: number): void {
  ctx.moveTo(x, y + r * 0.9);
  ctx.bezierCurveTo(
    x - r * 0.5,
    y + r * 0.5,
    x - r,
    y + r * 0.25,
    x - r,
    y - r * 0.15,
  );
  ctx.arc(x - r * 0.5, y - r * 0.3, r * 0.52, 160 * RAD, 340 * RAD, false);
  ctx.arc(x + r * 0.5, y - r * 0.3, r * 0.52, 200 * RAD, 20 * RAD, false);
  ctx.bezierCurveTo(
    x + r,
    y + r * 0.25,
    x + r * 0.5,
    y + r * 0.5,
    x,
    y + r * 0.9,
  );
  ctx.closePath();
}

/** A raindrop / seed: round at the bottom, pointed on top. */
function drop(ctx: Ctx, x: number, y: number, r: number): void {
  ctx.moveTo(x, y - r * 1.2);
  ctx.quadraticCurveTo(x + r * 0.55, y - r * 0.35, x + r * 0.6, y + r * 0.2);
  ctx.arc(x, y + r * 0.2, r * 0.6, 0, 180 * RAD, false);
  ctx.quadraticCurveTo(x - r * 0.55, y - r * 0.35, x, y - r * 1.2);
  ctx.closePath();
}

function snowflake(ctx: Ctx, x: number, y: number, r: number): void {
  for (let i = 0; i < 6; i++) {
    const a = (i * Math.PI) / 3;
    ctx.moveTo(x, y);
    ctx.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r);
    const mx = x + Math.cos(a) * r * 0.6,
      my = y + Math.sin(a) * r * 0.6;
    for (const side of [-1, 1]) {
      const b = a + (side * Math.PI) / 4;
      ctx.moveTo(mx, my);
      ctx.lineTo(mx + Math.cos(b) * r * 0.3, my + Math.sin(b) * r * 0.3);
    }
  }
}

function clover(ctx: Ctx, r: number, color: string): void {
  for (let i = 0; i < 3; i++) {
    const a = (i * 2 * Math.PI) / 3 - Math.PI / 2;
    ctx.beginPath();
    heart(ctx, Math.cos(a) * r * 0.55, Math.sin(a) * r * 0.55, r * 0.6);
    ctx.fillStyle = color;
    ctx.fill();
  }
  ctx.beginPath();
  ctx.moveTo(0, r * 0.2);
  ctx.quadraticCurveTo(0, r, r * 0.35, r * 1.3);
  ctx.strokeStyle = color;
  ctx.lineWidth = Math.max(0.6, r * 0.18);
  ctx.lineCap = "round";
  ctx.stroke();
}

function flower(
  ctx: Ctx,
  x: number,
  y: number,
  r: number,
  petal: string,
  centre: string,
): void {
  for (let i = 0; i < 5; i++) {
    const a = (i * 2 * Math.PI) / 5 - Math.PI / 2;
    const cx = x + Math.cos(a) * r * 0.55,
      cy = y + Math.sin(a) * r * 0.55;
    fillEllipse(ctx, cx - r * 0.42, cy - r * 0.42, r * 0.84, r * 0.84, petal);
  }
  fillEllipse(ctx, x - r * 0.32, y - r * 0.32, r * 0.64, r * 0.64, centre);
}

const LEAF: [number, number][] = [
  [0, -1.0],
  [0.18, -0.55],
  [0.62, -0.72],
  [0.45, -0.25],
  [0.95, -0.05],
  [0.45, 0.2],
  [0.55, 0.62],
  [0.08, 0.42],
  [0, 0.9],
  [-0.08, 0.42],
  [-0.55, 0.62],
  [-0.45, 0.2],
  [-0.95, -0.05],
  [-0.45, -0.25],
  [-0.62, -0.72],
  [-0.18, -0.55],
];

/** A maple-ish leaf pointing up, centred on the origin. */
function leaf(ctx: Ctx, r: number): void {
  ctx.moveTo(LEAF[0][0] * r, LEAF[0][1] * r);
  for (let i = 1; i < LEAF.length; i++)
    ctx.lineTo(LEAF[i][0] * r, LEAF[i][1] * r);
  ctx.closePath();
}

/** Stroke the current path. Defaults match SwiftUI `lineWidth:` (butt caps, miter joins). */
function stroke(
  ctx: Ctx,
  style: string,
  width: number,
  cap: CanvasLineCap = "butt",
): void {
  ctx.strokeStyle = style;
  ctx.lineWidth = width;
  ctx.lineCap = cap;
  ctx.lineJoin = "miter";
  ctx.stroke();
}

// MARK: - Monthly Flames

function drawMonthly(
  ctx: Ctx,
  fx: Set<string>,
  w: number,
  h: number,
  s: number,
): void {
  if (!hasAny(fx, MONTHLY)) return;
  const px = (x: number) => x * w,
    py = (y: number) => y * h;

  if (fx.has("sunRays")) {
    const cx = px(0.5),
      cy = py(0.66);
    for (let i = 0; i < 12; i += 2) {
      const a0 = (i * Math.PI) / 6,
        a1 = a0 + Math.PI / 6;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + Math.cos(a0) * s * 1.2, cy + Math.sin(a0) * s * 1.2);
      ctx.lineTo(cx + Math.cos(a1) * s * 1.2, cy + Math.sin(a1) * s * 1.2);
      ctx.closePath();
      ctx.fillStyle = white(0.16);
      ctx.fill();
    }
    const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, s * 0.22);
    g.addColorStop(0, hx(0xfffbe0, 0.7));
    g.addColorStop(1, hx(0xfffbe0, 0));
    fillEllipse(ctx, cx - s * 0.22, cy - s * 0.22, s * 0.44, s * 0.44, g);
  }
  if (fx.has("pumpkinRibs")) {
    for (const x of [0.2, 0.35, 0.65, 0.8]) {
      ctx.beginPath();
      ctx.moveTo(px(0.5 + (x - 0.5) * 0.3), py(0.06));
      ctx.quadraticCurveTo(
        px(x + (x - 0.5) * 0.35),
        py(0.58),
        px(0.5 + (x - 0.5) * 0.8),
        py(1.02),
      );
      stroke(ctx, hx(0x8a3a06, 0.55), s * 0.03, "round");
    }
    for (const x of [0.28, 0.72])
      fillEllipse(
        ctx,
        (x - 0.04) * w,
        0.42 * h,
        0.06 * w,
        0.26 * h,
        hx(0xffd08a, 0.35),
      );
  }
  if (fx.has("melon")) {
    const rindTop = 0.86;
    fillRect(ctx, 0, rindTop * h, w, h, hx(0x2e8b3a));
    fillRect(ctx, 0, (rindTop - 0.03) * h, w, 0.035 * h, hx(0xf2ffe6));
    for (let i = 0; i < 9; i++)
      fillRect(ctx, i * 0.13 * w, rindTop * h, 0.05 * w, 0.2 * h, hx(0x1a5e24));
    const seeds: [number, number, number][] = [
      [0.3, 0.4, -20],
      [0.52, 0.3, 10],
      [0.7, 0.46, 25],
      [0.24, 0.66, -15],
      [0.46, 0.74, 5],
      [0.76, 0.7, 20],
      [0.6, 0.56, -10],
    ];
    for (const [x, y, r] of seeds) {
      ctx.save();
      ctx.translate(x * w, y * h);
      ctx.rotate(r * RAD);
      ctx.beginPath();
      drop(ctx, 0, 0, s * 0.028);
      ctx.fillStyle = hx(0x2a0e0e);
      ctx.fill();
      fillEllipse(
        ctx,
        -s * 0.006,
        -s * 0.012,
        s * 0.008,
        s * 0.012,
        white(0.6),
      );
      ctx.restore();
    }
  }
  if (fx.has("flagStripes")) {
    for (let i = 0; i < 4; i++)
      fillRect(ctx, 0, (0.5 + i * 0.13) * h, w, 0.065 * h, white(0.85));
    fillRect(ctx, 0, 0, 0.56 * w, 0.5 * h, hx(0x1e3a8a));
    for (const [x, y] of [
      [0.16, 0.3],
      [0.3, 0.22],
      [0.44, 0.3],
      [0.22, 0.42],
      [0.38, 0.42],
      [0.3, 0.12],
    ]) {
      fillStar(ctx, x * w, y * h, s * 0.035, 0.42, white());
    }
  }
  if (fx.has("knit")) {
    for (let row = 0; row < 14; row++) {
      const y = (0.04 + row * 0.072) * h;
      for (let col = 0; col < 10; col++) {
        const x = (col * 0.11 + (row % 2 === 0 ? 0 : 0.055)) * w;
        ctx.beginPath();
        ctx.moveTo(x, y);
        ctx.lineTo(x + 0.025 * w, y + 0.035 * h);
        ctx.lineTo(x + 0.05 * w, y);
        stroke(ctx, white(0.16), s * 0.01, "round");
      }
    }
    const bandY = 0.7 * h,
      bandH = 0.11 * h,
      midY = bandY + bandH / 2;
    fillRect(ctx, 0, bandY, w, bandH, hx(0xfff4e6, 0.92));
    for (let i = 0; i < 8; i++) {
      const x = (0.06 + i * 0.125) * w;
      ctx.beginPath();
      if (i % 2 === 0) heart(ctx, x, midY, s * 0.04);
      else
        ellipseIn(ctx, x - s * 0.012, midY - s * 0.012, s * 0.024, s * 0.024);
      ctx.fillStyle = hx(0xc0384a);
      ctx.fill();
    }
  }
  if (fx.has("rainbow")) {
    const cx = px(0.5),
      cy = py(1.08);
    const bands = [0xff6b6b, 0xffb347, 0xffe66b, 0x7fe08a, 0x6bb8ff, 0xb08aff];
    bands.forEach((col, i) => {
      const r = s * (0.52 - i * 0.045);
      ctx.beginPath();
      ctx.arc(cx, cy, r, 180 * RAD, 360 * RAD, false);
      stroke(ctx, hx(col, 0.75), s * 0.045);
    });
  }
  if (fx.has("snowflakes")) {
    const flakes: [number, number, number][] = [
      [0.5, 0.16, 0.9],
      [0.3, 0.36, 0.7],
      [0.72, 0.4, 0.8],
      [0.22, 0.66, 0.6],
      [0.8, 0.7, 0.7],
      [0.52, 0.86, 0.6],
      [0.4, 0.56, 0.4],
      [0.64, 0.24, 0.45],
    ];
    for (const [x, y, k] of flakes) {
      ctx.beginPath();
      snowflake(ctx, x * w, y * h, s * 0.06 * k);
      stroke(ctx, white(0.85), Math.max(0.6, s * 0.011 * k), "round");
    }
  }
  if (fx.has("hearts")) {
    const spots: [number, number, number, number][] = [
      [0.5, 0.16, 0.8, 0],
      [0.28, 0.38, 0.7, -15],
      [0.74, 0.4, 0.8, 12],
      [0.2, 0.68, 0.6, -10],
      [0.8, 0.7, 0.7, 15],
      [0.5, 0.88, 0.6, 0],
      [0.62, 0.26, 0.45, 20],
      [0.36, 0.82, 0.45, -20],
    ];
    spots.forEach(([x, y, k, r], i) => {
      ctx.save();
      ctx.translate(x * w, y * h);
      ctx.rotate(r * RAD);
      ctx.beginPath();
      heart(ctx, 0, 0, s * 0.07 * k);
      ctx.fillStyle = i % 2 === 0 ? white(0.8) : hx(0xffb3c9, 0.9);
      ctx.fill();
      ctx.restore();
    });
  }
  if (fx.has("clovers")) {
    const spots: [number, number, number, number][] = [
      [0.5, 0.18, 0.8, 0],
      [0.28, 0.42, 0.7, -20],
      [0.74, 0.44, 0.7, 15],
      [0.22, 0.72, 0.6, 10],
      [0.78, 0.74, 0.6, -10],
      [0.5, 0.88, 0.55, 5],
    ];
    for (const [x, y, k, r] of spots) {
      ctx.save();
      ctx.translate(x * w, y * h);
      ctx.rotate(r * RAD);
      clover(ctx, s * 0.06 * k, hx(0xe8ffd2, 0.75));
      ctx.restore();
    }
    for (const [x, y] of [
      [0.4, 0.3],
      [0.64, 0.62],
      [0.34, 0.58],
      [0.6, 0.8],
    ]) {
      fillStar(ctx, x * w, y * h, s * 0.022, 0.3, hx(0xffd84a));
    }
  }
  if (fx.has("raindrops")) {
    const drops: [number, number, number][] = [
      [0.46, 0.14, 0.8],
      [0.3, 0.3, 0.7],
      [0.66, 0.28, 0.9],
      [0.22, 0.5, 0.6],
      [0.78, 0.52, 0.7],
      [0.5, 0.44, 0.5],
      [0.36, 0.66, 0.55],
      [0.64, 0.68, 0.6],
    ];
    for (const [x, y, k] of drops) {
      ctx.beginPath();
      drop(ctx, x * w, y * h, s * 0.05 * k);
      ctx.fillStyle = white(0.8);
      ctx.fill();
    }
  }
  if (fx.has("flowers")) {
    const spots: [number, number, number, number][] = [
      [0.5, 0.18, 0.8, 0xffffff],
      [0.28, 0.4, 0.7, 0xff8fb8],
      [0.74, 0.42, 0.8, 0xffe066],
      [0.22, 0.7, 0.6, 0xb89bff],
      [0.78, 0.72, 0.7, 0xffffff],
      [0.5, 0.86, 0.6, 0xff8fb8],
    ];
    for (const [x, y, k, col] of spots)
      flower(ctx, x * w, y * h, s * 0.06 * k, hx(col, 0.92), hx(0xffb020));
  }
  if (fx.has("leaves")) {
    const spots: [number, number, number, number, number][] = [
      [0.5, 0.18, 0.8, -15, 0xffe07a],
      [0.28, 0.42, 0.75, 25, 0xb8320e],
      [0.74, 0.44, 0.8, -30, 0xffd24a],
      [0.22, 0.72, 0.6, 40, 0xffe07a],
      [0.78, 0.74, 0.65, -10, 0x8a2a08],
      [0.5, 0.86, 0.6, 15, 0xb8320e],
    ];
    for (const [x, y, k, r, col] of spots) {
      ctx.save();
      ctx.translate(x * w, y * h);
      ctx.rotate(r * RAD);
      ctx.beginPath();
      leaf(ctx, s * 0.07 * k);
      ctx.fillStyle = hx(col, 0.9);
      ctx.fill();
      ctx.beginPath();
      ctx.moveTo(0, s * 0.07 * k);
      ctx.lineTo(0, -s * 0.05 * k);
      stroke(ctx, hx(0x5a1a04, 0.55), Math.max(0.5, s * 0.006));
      ctx.restore();
    }
  }
  if (fx.has("stringLights")) {
    const bulbs = [0xff4f5e, 0xffd24a, 0x4fa8ff, 0xff8fd0, 0xffffff];
    let k = 0;
    for (const [y0, y1] of [
      [0.3, 0.42],
      [0.62, 0.74],
    ]) {
      ctx.beginPath();
      ctx.moveTo(px(-0.05), py(y0));
      ctx.quadraticCurveTo(px(0.5), py(y1 * 2 - y0), px(1.05), py(y0));
      stroke(ctx, hx(0x0a2a14, 0.85), Math.max(0.6, s * 0.01));
      for (const t of [0.12, 0.31, 0.5, 0.69, 0.88]) {
        const x = -0.05 + t * 1.1;
        const y = y0 + (y1 - y0) * 4 * t * (1 - t) * 1.0;
        const col = bulbs[k % bulbs.length];
        k += 1;
        const cx = px(x),
          cy = py(y + 0.02);
        ctx.save();
        ctx.filter = `blur(${s * 0.025}px)`;
        fillEllipse(
          ctx,
          cx - s * 0.045,
          cy - s * 0.045,
          s * 0.09,
          s * 0.09,
          hx(col, 0.7),
        );
        ctx.restore();
        fillEllipse(
          ctx,
          cx - s * 0.018,
          cy - s * 0.012,
          s * 0.036,
          s * 0.05,
          hx(col),
        );
      }
    }
  }
}

// MARK: - Body / inner

/**
 * Draws the body effects in the OUTER shape's frame: (0,0)-(w,h) in canvas
 * units, `unit` = the figure size (Swift `size`). Clips to the outer shape
 * itself (as Swift does), so a caller clip is optional. Still frame: Prism's
 * colour cycle at rotation 0. `halo`/`embers`/`hotCore` are not drawn here.
 */
export function drawBodyFx(
  ctx: CanvasRenderingContext2D,
  p: PaletteJson,
  w: number,
  h: number,
  unit: number,
): void {
  const fx = effectSet(p);
  const prism = fx.has("prismCycle") && (p.outer?.length ?? 0) > 0;
  if (!prism && !hasAny(fx, DRAWN_HERE)) return;
  const size = unit;
  const px = (x: number) => x * w,
    py = (y: number) => y * h;

  ctx.save();
  ctx.beginPath();
  traceOuterShape(ctx, w, h);
  ctx.clip();

  if (prism) {
    // AngularGradient(colors: outer + [outer[0]], center: (0.5, 0.62)) filling
    // the frame, .scaleEffect(1.6) about the frame centre, .opacity(0.55).
    // A uniform scale keeps the angles, so it is one conic gradient whose
    // centre moved 1.6x away from the frame centre.
    const stops = (p.outer as string[])
      .concat([(p.outer as string[])[0]])
      .map(cssColor);
    const cx = w * 0.5,
      cy = h * 0.5 + 1.6 * (0.62 - 0.5) * h;
    const g = ctx.createConicGradient(0, cx, cy);
    stops.forEach((c, i) =>
      g.addColorStop(stops.length === 1 ? 0 : i / (stops.length - 1), c),
    );
    ctx.save();
    ctx.globalAlpha = 0.55;
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
    ctx.restore();
  }

  drawMonthly(ctx, fx, w, h, size);

  if (fx.has("nebula")) {
    ctx.save();
    ctx.filter = `blur(${size * 0.05}px)`;
    fillEllipse(ctx, 0.05 * w, 0.45 * h, 0.55 * w, 0.3 * h, hx(0xb5389a, 0.55));
    fillEllipse(ctx, 0.45 * w, 0.25 * h, 0.45 * w, 0.3 * h, hx(0x3a6bff, 0.5));
    ctx.restore();
  }
  if (fx.has("waves")) {
    [0.52, 0.66, 0.8].forEach((yy, i) => {
      ctx.beginPath();
      ctx.moveTo(px(-0.05), py(yy));
      for (let j = 0; j <= 24; j++) {
        const t = j / 24;
        ctx.lineTo(
          px(-0.05 + t * 1.1),
          py(yy + 0.025 * Math.sin(t * 14 + i * 1.3)),
        );
      }
      stroke(ctx, white(0.42 - i * 0.08), size * 0.022, "round");
    });
  }
  if (fx.has("lava")) {
    const blobs: [number, number, number, number][] = [
      [0.22, 0.6, 0.16, 0.11],
      [0.7, 0.4, 0.12, 0.1],
      [0.46, 0.22, 0.08, 0.07],
      [0.78, 0.74, 0.1, 0.07],
      [0.3, 0.86, 0.12, 0.06],
    ];
    for (const b of blobs) {
      const rx = (b[0] - b[2]) * w,
        ry = (b[1] - b[3]) * h,
        rw = b[2] * 2 * w,
        rh = b[3] * 2 * h;
      const g = ctx.createLinearGradient(rx, ry, rx + rw, ry + rh);
      g.addColorStop(0, hx(0xffe36b, 1));
      g.addColorStop(1, hx(0xffa23a, 1));
      fillEllipse(ctx, rx, ry, rw, rh, g);
      fillEllipse(
        ctx,
        rx + rw * 0.2,
        ry + rh * 0.15,
        rw * 0.3,
        rh * 0.25,
        white(0.45),
      );
    }
  }
  if (fx.has("ribbons")) {
    const cols: [number, number, number, number][] = [
      [0x3dffb0, 0.85, 0.28, 0.0],
      [0xff6fd8, 0.6, 0.44, 1.3],
      [0x55c8ff, 0.7, 0.6, 2.2],
    ];
    for (const [hex, o, yy, ph] of cols) {
      const trace = () => {
        ctx.beginPath();
        ctx.moveTo(px(-0.1), py(yy));
        for (let i = 0; i <= 24; i++) {
          const t = i / 24;
          ctx.lineTo(
            px(-0.1 + t * 1.2),
            py(yy + 0.05 * Math.sin(t * 9 + ph) - t * 0.08),
          );
        }
      };
      ctx.save();
      ctx.filter = `blur(${size * 0.018}px)`;
      trace();
      stroke(ctx, hx(hex, o), size * 0.07, "round");
      ctx.restore();
      // `c.opacity(0.9)` multiplies the colour's own opacity.
      trace();
      stroke(ctx, hx(hex, o * 0.9), size * 0.012, "round");
    }
  }
  if (fx.has("candy")) {
    ctx.save();
    ctx.rotate(-30 * RAD);
    for (let i = -6; i <= 10; i++)
      fillRect(ctx, i * 0.16 * w, -h, 0.05 * w, h * 3, white(0.35));
    ctx.restore();
  }
  if (fx.has("stars") || fx.has("denseStars")) {
    const pts: [number, number, number][] = [
      [0.5, 0.14, 1.0],
      [0.4, 0.3, 0.6],
      [0.62, 0.34, 0.8],
      [0.3, 0.5, 0.9],
      [0.74, 0.55, 0.6],
      [0.18, 0.68, 0.7],
      [0.84, 0.7, 0.9],
      [0.24, 0.84, 0.5],
      [0.7, 0.88, 0.7],
      [0.54, 0.46, 0.5],
      [0.12, 0.76, 0.5],
      [0.88, 0.8, 0.5],
    ];
    if (fx.has("denseStars")) {
      pts.push(
        [0.45, 0.22, 0.4],
        [0.58, 0.24, 0.5],
        [0.35, 0.4, 0.4],
        [0.68, 0.44, 0.45],
        [0.22, 0.58, 0.4],
        [0.8, 0.62, 0.4],
        [0.15, 0.62, 0.5],
        [0.35, 0.92, 0.45],
        [0.6, 0.95, 0.4],
        [0.88, 0.62, 0.35],
        [0.48, 0.6, 0.3],
      );
    }
    for (const [x, y, r] of pts) {
      const rr = Math.max(0.5, size * 0.012 * r);
      fillEllipse(ctx, x * w - rr, y * h - rr, rr * 2, rr * 2, white(0.95));
    }
    for (const [x, y] of [
      [0.36, 0.24],
      [0.7, 0.62],
      [0.22, 0.76],
    ])
      fillStar(ctx, x * w, y * h, size * 0.035, 0.25, white());
  }
  if (fx.has("sheen")) {
    ctx.save();
    ctx.rotate(-24 * RAD);
    fillRect(ctx, -0.05 * w, 0.1 * h, 0.16 * w, h * 1.4, white(0.4));
    fillRect(ctx, 0.16 * w, 0.1 * h, 0.05 * w, h * 1.4, white(0.28));
    ctx.restore();
  }
  ctx.restore();
}

/**
 * Same for the INNER shape's frame (size*0.54 x size*0.58, offset y by
 * size*0.13 from the body's centre in FlameBuddyFigure). Only `hotCore`
 * (Eternal's white-hot core) lives here. Clips to the inner shape itself.
 */
export function drawInnerFx(
  ctx: CanvasRenderingContext2D,
  p: PaletteJson,
  w: number,
  h: number,
  unit: number,
): void {
  if (!effectSet(p).has("hotCore")) return;
  const cx = 0.5 * w,
    cy = 0.7 * h;
  const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, unit * 0.3);
  g.addColorStop(0, white(1));
  g.addColorStop(1, white(0));
  ctx.save();
  ctx.beginPath();
  traceInnerShape(ctx, w, h);
  ctx.fillStyle = g;
  ctx.fill();
  ctx.restore();
}
