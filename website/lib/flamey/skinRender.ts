// Draws a recorded skin layer (ops in body units, docs/flamey-skins.md) on a
// canvas 2D context that is already transformed so 1 unit = u pixels and
// (0, 0) = the centre of Flamey's square. THE web renderer: the Skin Builder
// (/admin/skins) draws with it, and app/FlameyExport/convert/match.mjs loads
// this very file (types stripped by Node) to diff it against the Swift
// renderer's reference images. The Swift renderer implements the same rules.
//
// Keep this file erasable TypeScript with no imports (no enums, no
// namespaces, no parameter properties): match.mjs runs it through
// `module.stripTypeScriptTypes` and serves it to a headless browser as-is.

export type Hex8 = string;
export type TokenPaint = { tok: string; a?: number; fb: Hex8 };
export type Colour = Hex8 | TokenPaint;
export type Stop = [number, Colour];
export type GradientPaint =
  | { lin: [number, number, number, number]; stops: Stop[] }
  | { rad: [number, number, number, number]; stops: Stop[] }
  | { conic: [number, number, number]; stops: Stop[] };
export type Paint = Colour | GradientPaint;
export type Matrix = [number, number, number, number, number, number];
export type Effect = { blur: number } | { shadow: [Hex8, number, number, number] };

type OpBase = { m?: Matrix; a?: number; fx?: Effect[]; clip?: number[] };
export type FillOp = OpBase & { op: "fill"; d: string; paint: Paint; eo?: boolean };
export type StrokeOp = OpBase & {
  op: "stroke";
  d: string;
  paint: Paint;
  w: number;
  cap?: "round" | "square" | "butt";
  join?: "round" | "bevel" | "miter";
  miter?: number;
  dash?: number[];
  phase?: number;
};
export type ImageOp = OpBase & { op: "image"; src: string; rect: [number, number, number, number] };
export type Op = FillOp | StrokeOp | ImageOp;
export type Clip = { d: string; eo?: boolean; inv?: boolean };
export type Recording = { ops: Op[]; clips?: Clip[]; images?: Record<string, string> };

export type DrawOptions = {
  /** Canvas blur is sigma; SwiftUI's radius isn't exactly sigma (calibrated by match.mjs). */
  blurScale?: number;
  shadowScale?: number;
  /** token ("outer.1") -> "#RRGGBB" or "#RRGGBBAA"; absent = each token's fallback. */
  palette?: Record<string, string> | null;
  /** Multiplies every op's opacity. */
  alpha?: number;
};

/** Anything drawImage accepts; kept structural so this file needs no DOM lib quirks. */
export type ImageMap = Record<string, CanvasImageSource>;

export function rgba(hex8: string): string {
  const h = hex8.replace("#", "");
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  const a = h.length >= 8 ? parseInt(h.slice(6, 8), 16) / 255 : 1;
  return `rgba(${r},${g},${b},${a.toFixed(4)})`;
}

export function withAlpha(hex8: string, k: number): string {
  const h = hex8.replace("#", "");
  const a = (h.length >= 8 ? parseInt(h.slice(6, 8), 16) / 255 : 1) * k;
  return "#" + h.slice(0, 6) + Math.round(Math.max(0, Math.min(1, a)) * 255).toString(16).padStart(2, "0");
}

export function colour(c: Colour, opts?: DrawOptions): string {
  if (typeof c === "string") return c;
  if (c && c.tok) {
    const base = opts && opts.palette && opts.palette[c.tok];
    if (!base) return c.fb;
    return withAlpha(base.length === 7 ? base + "FF" : base, c.a ?? 1);
  }
  return "#000000FF";
}

function paintStyle(ctx: CanvasRenderingContext2D, p: Paint, opts: DrawOptions): string | CanvasGradient {
  if (typeof p === "string" || (p && "tok" in p)) return rgba(colour(p as Colour, opts));
  let g: CanvasGradient;
  if ("lin" in p) g = ctx.createLinearGradient(p.lin[0], p.lin[1], p.lin[2], p.lin[3]);
  else if ("rad" in p) g = ctx.createRadialGradient(p.rad[0], p.rad[1], p.rad[2], p.rad[0], p.rad[1], p.rad[3]);
  else if ("conic" in p) g = ctx.createConicGradient((p.conic[2] * Math.PI) / 180, p.conic[0], p.conic[1]);
  else return "black";
  for (const [t, c] of p.stops) g.addColorStop(Math.max(0, Math.min(1, t)), rgba(colour(c, opts)));
  return g;
}

const pathCache = new Map<string, Path2D>();
function path(d: string): Path2D {
  let p = pathCache.get(d);
  if (!p) {
    p = new Path2D(d);
    pathCache.set(d, p);
  }
  return p;
}

function applyClips(ctx: CanvasRenderingContext2D, rec: Recording, ids: number[] | undefined) {
  for (const id of ids || []) {
    const c = rec.clips?.[id];
    if (!c) continue;
    if (c.inv) {
      const p = new Path2D();
      p.rect(-50, -50, 100, 100);
      p.addPath(path(c.d));
      ctx.clip(p, "evenodd");
    } else {
      ctx.clip(path(c.d), c.eo ? "evenodd" : "nonzero");
    }
  }
}

/** Pixels per unit of the current transform (filters are in px). */
function pxPerUnit(ctx: CanvasRenderingContext2D): number {
  const m = ctx.getTransform();
  return Math.sqrt(Math.abs(m.a * m.d - m.b * m.c));
}

export function drawLayer(
  ctx: CanvasRenderingContext2D,
  rec: Recording | null | undefined,
  opts: DrawOptions = {},
  images: ImageMap = {},
): void {
  if (!rec || !rec.ops) return;
  const k = pxPerUnit(ctx);
  for (const op of rec.ops) {
    ctx.save();
    applyClips(ctx, rec, op.clip);
    ctx.globalAlpha = (op.a ?? 1) * (opts.alpha ?? 1);
    for (const f of op.fx || []) {
      if ("blur" in f) ctx.filter = `blur(${f.blur * k * (opts.blurScale ?? 1)}px)`;
      if ("shadow" in f) {
        ctx.shadowColor = rgba(f.shadow[0]);
        ctx.shadowBlur = f.shadow[1] * k * (opts.shadowScale ?? 1);
        ctx.shadowOffsetX = f.shadow[2] * k;
        ctx.shadowOffsetY = f.shadow[3] * k;
      }
    }
    if (op.m) ctx.transform(op.m[0], op.m[1], op.m[2], op.m[3], op.m[4], op.m[5]);
    if (op.op === "fill") {
      ctx.fillStyle = paintStyle(ctx, op.paint, opts);
      ctx.fill(path(op.d), op.eo ? "evenodd" : "nonzero");
    } else if (op.op === "stroke") {
      ctx.strokeStyle = paintStyle(ctx, op.paint, opts);
      ctx.lineWidth = op.w;
      ctx.lineCap = op.cap || "butt";
      ctx.lineJoin = op.join || "miter";
      ctx.miterLimit = op.miter || 10;
      ctx.setLineDash(op.dash || []);
      ctx.lineDashOffset = op.phase || 0;
      ctx.stroke(path(op.d));
    } else if (op.op === "image") {
      const img = images[op.src];
      if (img) ctx.drawImage(img, op.rect[0], op.rect[1], op.rect[2], op.rect[3]);
    }
    ctx.restore();
  }
}
