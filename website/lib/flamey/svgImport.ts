// SVG drawn on the Skin Builder template -> a skin recording (ops in body
// units, docs/flamey-skins.md). Browser only (DOMParser, a canvas to resolve
// CSS colours).
//
// The SVG's viewBox is the template's 3x3 stage, so any viewBox maps
// linearly onto [-1.5, 1.5]. Every arc / H / V / S / T becomes M L Q C Z.
// Transforms are baked into coordinates; where a transform is not a
// similarity and the element is stroked (or its gradient is skewed by it),
// the op keeps its local geometry and carries the transform in "m".

import type { Clip, Colour, GradientPaint, Matrix, Op, Paint, Recording, Stop } from "./skinRender";

/** Template layers the importer skips (by id, and anything inside them). */
export const IGNORED_IDS = ["guides", "reference", "flamey-reference"];

export type ImportResult = { recording: Recording; warnings: string[]; bounds: [number, number, number, number] | null };

// ---------------------------------------------------------------- matrices

type M = [number, number, number, number, number, number]; // a b c d e f
const I: M = [1, 0, 0, 1, 0, 0];
const mul = (p: M, q: M): M => [
  p[0] * q[0] + p[2] * q[1],
  p[1] * q[0] + p[3] * q[1],
  p[0] * q[2] + p[2] * q[3],
  p[1] * q[2] + p[3] * q[3],
  p[0] * q[4] + p[2] * q[5] + p[4],
  p[1] * q[4] + p[3] * q[5] + p[5],
];
const apply = (m: M, x: number, y: number): [number, number] => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
const det = (m: M) => m[0] * m[3] - m[1] * m[2];
const inv = (m: M): M => {
  const d = det(m) || 1e-12;
  return [m[3] / d, -m[1] / d, -m[2] / d, m[0] / d, (m[2] * m[5] - m[3] * m[4]) / d, (m[1] * m[4] - m[0] * m[5]) / d];
};
/** Uniform scale (+ rotation/reflection): columns orthogonal and equally long. */
const isSimilarity = (m: M) => {
  const l1 = Math.hypot(m[0], m[1]);
  const l2 = Math.hypot(m[2], m[3]);
  const dot = m[0] * m[2] + m[1] * m[3];
  return Math.abs(l1 - l2) <= 1e-6 * Math.max(l1, l2, 1e-9) + 1e-9 && Math.abs(dot) <= 1e-6 * l1 * l2 + 1e-12;
};
const scaleOf = (m: M) => Math.sqrt(Math.abs(det(m)));

function parseTransform(s: string | null): M {
  if (!s) return I;
  let m: M = I;
  const re = /(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)/g;
  let hit: RegExpExecArray | null;
  while ((hit = re.exec(s))) {
    const n = (hit[2].match(/[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g) || []).map(Number);
    let t: M = I;
    switch (hit[1]) {
      case "matrix":
        if (n.length === 6) t = n as M;
        break;
      case "translate":
        t = [1, 0, 0, 1, n[0] || 0, n[1] || 0];
        break;
      case "scale":
        t = [n[0] ?? 1, 0, 0, n[1] ?? n[0] ?? 1, 0, 0];
        break;
      case "rotate": {
        const a = ((n[0] || 0) * Math.PI) / 180;
        const r: M = [Math.cos(a), Math.sin(a), -Math.sin(a), Math.cos(a), 0, 0];
        if (n.length >= 3) t = mul(mul([1, 0, 0, 1, n[1], n[2]], r), [1, 0, 0, 1, -n[1], -n[2]]);
        else t = r;
        break;
      }
      case "skewX":
        t = [1, 0, Math.tan(((n[0] || 0) * Math.PI) / 180), 1, 0, 0];
        break;
      case "skewY":
        t = [1, Math.tan(((n[0] || 0) * Math.PI) / 180), 0, 1, 0, 0];
        break;
    }
    m = mul(m, t);
  }
  return m;
}

// ---------------------------------------------------------------- paths

/** Absolute segments: M L Q C Z only. */
type Seg = { c: "M" | "L" | "Q" | "C" | "Z"; p: number[] };

function tokenize(d: string): (string | number)[] {
  const out: (string | number)[] = [];
  const re = /([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)/g;
  let hit: RegExpExecArray | null;
  while ((hit = re.exec(d))) out.push(hit[1] ? hit[1] : Number(hit[2]));
  return out;
}

/** Arc flags may be written without separators ("a1 1 0 011 1"). */
function tokenizeArcAware(d: string): (string | number)[] {
  const out: (string | number)[] = [];
  let i = 0;
  let cmd = "";
  let argIndex = 0;
  const num = /^[\s,]*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)/;
  while (i < d.length) {
    const ch = d[i];
    if (/\s|,/.test(ch)) {
      i++;
      continue;
    }
    if (/[MmLlHhVvCcSsQqTtAaZz]/.test(ch)) {
      cmd = ch;
      argIndex = 0;
      out.push(ch);
      i++;
      continue;
    }
    if ((cmd === "a" || cmd === "A") && (argIndex % 7 === 3 || argIndex % 7 === 4) && (ch === "0" || ch === "1")) {
      out.push(Number(ch));
      argIndex++;
      i++;
      continue;
    }
    const m = num.exec(d.slice(i));
    if (!m) {
      i++;
      continue;
    }
    out.push(Number(m[1]));
    argIndex++;
    i += m[0].length;
  }
  return out;
}

function arcToCubics(x1: number, y1: number, rx: number, ry: number, phiDeg: number, fa: number, fs: number, x2: number, y2: number): number[][] {
  if (rx === 0 || ry === 0) return [[x1, y1, x2, y2, x2, y2]];
  const phi = (phiDeg * Math.PI) / 180;
  const cos = Math.cos(phi);
  const sin = Math.sin(phi);
  const dx = (x1 - x2) / 2;
  const dy = (y1 - y2) / 2;
  const x1p = cos * dx + sin * dy;
  const y1p = -sin * dx + cos * dy;
  rx = Math.abs(rx);
  ry = Math.abs(ry);
  const lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lam > 1) {
    rx *= Math.sqrt(lam);
    ry *= Math.sqrt(lam);
  }
  const num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
  const den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
  let k = Math.sqrt(Math.max(0, num / den));
  if (fa === fs) k = -k;
  const cxp = (k * rx * y1p) / ry;
  const cyp = (-k * ry * x1p) / rx;
  const cx = cos * cxp - sin * cyp + (x1 + x2) / 2;
  const cy = sin * cxp + cos * cyp + (y1 + y2) / 2;
  const ang = (ux: number, uy: number, vx: number, vy: number) => {
    const a = Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    return a;
  };
  const t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  let dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
  if (!fs && dt > 0) dt -= 2 * Math.PI;
  if (fs && dt < 0) dt += 2 * Math.PI;
  const n = Math.max(1, Math.ceil(Math.abs(dt) / (Math.PI / 2) - 1e-9));
  const step = dt / n;
  const alpha = (4 / 3) * Math.tan(step / 4);
  const out: number[][] = [];
  const pt = (t: number): [number, number] => {
    const ex = rx * Math.cos(t);
    const ey = ry * Math.sin(t);
    return [cos * ex - sin * ey + cx, sin * ex + cos * ey + cy];
  };
  const der = (t: number): [number, number] => {
    const ex = -rx * Math.sin(t);
    const ey = ry * Math.cos(t);
    return [cos * ex - sin * ey, sin * ex + cos * ey];
  };
  let ta = t1;
  for (let i = 0; i < n; i++) {
    const tb = ta + step;
    const [ax, ay] = pt(ta);
    const [bx, by] = pt(tb);
    const [dax, day] = der(ta);
    const [dbx, dby] = der(tb);
    out.push([ax + alpha * dax, ay + alpha * day, bx - alpha * dbx, by - alpha * dby, bx, by]);
    ta = tb;
  }
  // Land exactly on the endpoint.
  const last = out[out.length - 1];
  last[4] = x2;
  last[5] = y2;
  return out;
}

/** SVG path data (any commands) -> absolute M L Q C Z segments. */
export function normalizePath(d: string): Seg[] {
  const t = /[Aa]/.test(d) ? tokenizeArcAware(d) : tokenize(d);
  const segs: Seg[] = [];
  let i = 0;
  let cmd = "";
  let x = 0, y = 0, sx = 0, sy = 0;
  let lastC: [number, number] | null = null; // last cubic control 2
  let lastQ: [number, number] | null = null; // last quad control
  const n = () => {
    const v = t[i++];
    return typeof v === "number" ? v : NaN;
  };
  while (i < t.length) {
    if (typeof t[i] === "string") cmd = t[i++] as string;
    else if (!cmd) {
      i++;
      continue;
    }
    const rel = cmd === cmd.toLowerCase();
    const C = cmd.toUpperCase();
    const ox = rel ? x : 0;
    const oy = rel ? y : 0;
    let nextC: [number, number] | null = null;
    let nextQ: [number, number] | null = null;
    if (C === "Z") {
      segs.push({ c: "Z", p: [] });
      x = sx;
      y = sy;
      lastC = lastQ = null;
      // Z takes no args; a following number is malformed — skip until a command.
      while (i < t.length && typeof t[i] === "number") i++;
      continue;
    }
    if (C === "M") {
      x = ox + n();
      y = oy + n();
      sx = x;
      sy = y;
      segs.push({ c: "M", p: [x, y] });
      cmd = rel ? "l" : "L"; // implicit lineto
    } else if (C === "L") {
      x = ox + n();
      y = oy + n();
      segs.push({ c: "L", p: [x, y] });
    } else if (C === "H") {
      x = ox + n();
      segs.push({ c: "L", p: [x, y] });
    } else if (C === "V") {
      y = (rel ? y : 0) + n();
      segs.push({ c: "L", p: [x, y] });
    } else if (C === "C") {
      const p = [ox + n(), oy + n(), ox + n(), oy + n(), ox + n(), oy + n()];
      segs.push({ c: "C", p });
      nextC = [p[2], p[3]];
      x = p[4];
      y = p[5];
    } else if (C === "S") {
      const r1: [number, number] = lastC ? [2 * x - lastC[0], 2 * y - lastC[1]] : [x, y];
      const p = [r1[0], r1[1], ox + n(), oy + n(), ox + n(), oy + n()];
      segs.push({ c: "C", p });
      nextC = [p[2], p[3]];
      x = p[4];
      y = p[5];
    } else if (C === "Q") {
      const p = [ox + n(), oy + n(), ox + n(), oy + n()];
      segs.push({ c: "Q", p });
      nextQ = [p[0], p[1]];
      x = p[2];
      y = p[3];
    } else if (C === "T") {
      const q: [number, number] = lastQ ? [2 * x - lastQ[0], 2 * y - lastQ[1]] : [x, y];
      const p = [q[0], q[1], ox + n(), oy + n()];
      segs.push({ c: "Q", p });
      nextQ = q;
      x = p[2];
      y = p[3];
    } else if (C === "A") {
      const rx = n(), ry = n(), phi = n(), fa = n(), fs = n();
      const ex = ox + n();
      const ey = oy + n();
      for (const c of arcToCubics(x, y, rx, ry, phi, fa ? 1 : 0, fs ? 1 : 0, ex, ey)) segs.push({ c: "C", p: c });
      x = ex;
      y = ey;
    } else {
      i++;
    }
    lastC = nextC;
    lastQ = nextQ;
    if (segs.length && segs[segs.length - 1].p.some((v) => Number.isNaN(v))) {
      segs.pop();
      break; // ran out of numbers
    }
  }
  return segs;
}

const transformSegs = (segs: Seg[], m: M): Seg[] =>
  segs.map((s) => {
    const p: number[] = [];
    for (let k = 0; k < s.p.length; k += 2) p.push(...apply(m, s.p[k], s.p[k + 1]));
    return { c: s.c, p };
  });

/** Exact bounds (curve extrema, not control points). */
function segBounds(segs: Seg[]): [number, number, number, number] | null {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  const add = (x: number, y: number) => {
    x0 = Math.min(x0, x);
    y0 = Math.min(y0, y);
    x1 = Math.max(x1, x);
    y1 = Math.max(y1, y);
  };
  let cx = 0, cy = 0;
  for (const s of segs) {
    if (s.c === "M" || s.c === "L") {
      add(s.p[0], s.p[1]);
      cx = s.p[0];
      cy = s.p[1];
    } else if (s.c === "Q") {
      const [qx, qy, ex, ey] = s.p;
      add(ex, ey);
      for (const [a, b, c] of [[cx, qx, ex], [cy, qy, ey]]) {
        const den = a - 2 * b + c;
        if (Math.abs(den) > 1e-12) {
          const tt = (a - b) / den;
          if (tt > 0 && tt < 1) {
            const px = (1 - tt) * (1 - tt) * cx + 2 * (1 - tt) * tt * qx + tt * tt * ex;
            const py = (1 - tt) * (1 - tt) * cy + 2 * (1 - tt) * tt * qy + tt * tt * ey;
            add(px, py);
          }
        }
      }
      cx = ex;
      cy = ey;
    } else if (s.c === "C") {
      const [ax, ay, bx, by, ex, ey] = s.p;
      add(ex, ey);
      const at = (tt: number) => {
        const u = 1 - tt;
        add(
          u * u * u * cx + 3 * u * u * tt * ax + 3 * u * tt * tt * bx + tt * tt * tt * ex,
          u * u * u * cy + 3 * u * u * tt * ay + 3 * u * tt * tt * by + tt * tt * tt * ey,
        );
      };
      for (const [p0, p1, p2, p3] of [[cx, ax, bx, ex], [cy, ay, by, ey]]) {
        const a = -p0 + 3 * p1 - 3 * p2 + p3;
        const b = 2 * (p0 - 2 * p1 + p2);
        const c = p1 - p0;
        if (Math.abs(a) < 1e-12) {
          if (Math.abs(b) > 1e-12) {
            const tt = -c / b;
            if (tt > 0 && tt < 1) at(tt);
          }
        } else {
          const disc = b * b - 4 * a * c;
          if (disc >= 0) {
            for (const sg of [1, -1]) {
              const tt = (-b + sg * Math.sqrt(disc)) / (2 * a);
              if (tt > 0 && tt < 1) at(tt);
            }
          }
        }
      }
      cx = ex;
      cy = ey;
    }
  }
  return x0 === Infinity ? null : [x0, y0, x1, y1];
}

/** "0.5" -> ".5", "-0.5" -> "-.5", four decimals: the skin files' style. */
export function fmtNum(v: number, places = 4): string {
  let s = (Math.round(v * 10 ** places) / 10 ** places).toFixed(places).replace(/\.?0+$/, "");
  if (s === "-0") s = "0";
  return s.replace(/^(-?)0\./, "$1.");
}

function segsToD(segs: Seg[]): string {
  let out = "";
  for (const s of segs) {
    out += s.c;
    if (s.p.length) out += s.p.map((v) => fmtNum(v)).join(" ");
  }
  return out;
}

// ---------------------------------------------------------------- shapes

const K = 0.5522847498;

function ellipseSegs(cx: number, cy: number, rx: number, ry: number): Seg[] {
  return [
    { c: "M", p: [cx + rx, cy] },
    { c: "C", p: [cx + rx, cy + K * ry, cx + K * rx, cy + ry, cx, cy + ry] },
    { c: "C", p: [cx - K * rx, cy + ry, cx - rx, cy + K * ry, cx - rx, cy] },
    { c: "C", p: [cx - rx, cy - K * ry, cx - K * rx, cy - ry, cx, cy - ry] },
    { c: "C", p: [cx + K * rx, cy - ry, cx + rx, cy - K * ry, cx + rx, cy] },
    { c: "Z", p: [] },
  ];
}

function rectSegs(x: number, y: number, w: number, h: number, rx: number, ry: number): Seg[] {
  if (rx <= 0 || ry <= 0) {
    return [
      { c: "M", p: [x, y] },
      { c: "L", p: [x + w, y] },
      { c: "L", p: [x + w, y + h] },
      { c: "L", p: [x, y + h] },
      { c: "Z", p: [] },
    ];
  }
  rx = Math.min(rx, w / 2);
  ry = Math.min(ry, h / 2);
  const kx = K * rx, ky = K * ry;
  return [
    { c: "M", p: [x + rx, y] },
    { c: "L", p: [x + w - rx, y] },
    { c: "C", p: [x + w - rx + kx, y, x + w, y + ry - ky, x + w, y + ry] },
    { c: "L", p: [x + w, y + h - ry] },
    { c: "C", p: [x + w, y + h - ry + ky, x + w - rx + kx, y + h, x + w - rx, y + h] },
    { c: "L", p: [x + rx, y + h] },
    { c: "C", p: [x + rx - kx, y + h, x, y + h - ry + ky, x, y + h - ry] },
    { c: "L", p: [x, y + ry] },
    { c: "C", p: [x, y + ry - ky, x + rx - kx, y, x + rx, y] },
    { c: "Z", p: [] },
  ];
}

function pointsSegs(points: string, close: boolean): Seg[] {
  const n = (points.match(/[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g) || []).map(Number);
  const segs: Seg[] = [];
  for (let k = 0; k + 1 < n.length; k += 2) segs.push({ c: k === 0 ? "M" : "L", p: [n[k], n[k + 1]] });
  if (close && segs.length) segs.push({ c: "Z", p: [] });
  return segs;
}

// ---------------------------------------------------------------- styles

type Style = Record<string, string>;
const INHERITED = new Set([
  "fill", "stroke", "stroke-width", "fill-opacity", "stroke-opacity", "stroke-linecap", "stroke-linejoin",
  "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset", "fill-rule", "clip-rule", "color", "visibility",
]);
const PRESENTATION = [
  ...INHERITED, "opacity", "clip-path", "display", "stop-color", "stop-opacity",
];

function parseDecl(s: string, into: Style) {
  for (const part of s.split(";")) {
    const i = part.indexOf(":");
    if (i < 0) continue;
    const k = part.slice(0, i).trim().toLowerCase();
    const v = part.slice(i + 1).trim().replace(/\s*!important$/, "");
    if (k) into[k] = v;
  }
}

/** `.cls { ... }` / `#id { ... }` / `tag { ... }` rules from <style> (Illustrator writes these). */
function parseStyleSheets(doc: Document): { sel: string; decl: Style }[] {
  const rules: { sel: string; decl: Style }[] = [];
  for (const el of Array.from(doc.getElementsByTagName("style"))) {
    const css = (el.textContent || "").replace(/\/\*[\s\S]*?\*\//g, "");
    const re = /([^{}]+)\{([^{}]*)\}/g;
    let hit: RegExpExecArray | null;
    while ((hit = re.exec(css))) {
      const decl: Style = {};
      parseDecl(hit[2], decl);
      for (const sel of hit[1].split(",")) rules.push({ sel: sel.trim(), decl });
    }
  }
  return rules;
}

function ownStyle(el: Element, sheet: { sel: string; decl: Style }[]): Style {
  const s: Style = {};
  for (const k of PRESENTATION) {
    const v = el.getAttribute(k);
    if (v !== null) s[k] = v.trim();
  }
  const classes = (el.getAttribute("class") || "").split(/\s+/).filter(Boolean);
  for (const r of sheet) {
    if (
      (r.sel.startsWith(".") && classes.includes(r.sel.slice(1))) ||
      (r.sel.startsWith("#") && el.getAttribute("id") === r.sel.slice(1)) ||
      r.sel === el.localName
    ) {
      Object.assign(s, r.decl);
    }
  }
  const inline = el.getAttribute("style");
  if (inline) parseDecl(inline, s);
  return s;
}

let colourCtx: CanvasRenderingContext2D | null = null;
/** Any CSS colour -> [r, g, b, a] (0–255, a 0–1), via a canvas; null if invalid. */
function cssColour(v: string): [number, number, number, number] | null {
  if (!colourCtx) colourCtx = document.createElement("canvas").getContext("2d");
  const ctx = colourCtx!;
  ctx.fillStyle = "#010203";
  ctx.fillStyle = v;
  const got = String(ctx.fillStyle);
  if (got === "#010203" && v.replace(/\s/g, "").toLowerCase() !== "#010203") {
    ctx.fillStyle = "#040506";
    ctx.fillStyle = v;
    if (String(ctx.fillStyle) === "#040506") return null;
  }
  const c = String(ctx.fillStyle);
  if (c.startsWith("#")) return [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16), 1];
  const m = c.match(/rgba?\(([^)]+)\)/);
  if (!m) return null;
  const p = m[1].split(",").map((x) => parseFloat(x));
  return [p[0], p[1], p[2], p[3] ?? 1];
}

const hex2 = (n: number) => Math.round(Math.max(0, Math.min(255, n))).toString(16).padStart(2, "0").toUpperCase();
function hex8(rgba: [number, number, number, number], alpha: number): string {
  return "#" + hex2(rgba[0]) + hex2(rgba[1]) + hex2(rgba[2]) + hex2(rgba[3] * alpha * 255);
}

const num = (v: string | undefined, d: number) => {
  if (v === undefined || v === "") return d;
  const n = parseFloat(v);
  return Number.isFinite(n) ? n : d;
};
const opacityVal = (v: string | undefined) => {
  if (v === undefined) return 1;
  const n = v.trim().endsWith("%") ? parseFloat(v) / 100 : parseFloat(v);
  return Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : 1;
};

// ---------------------------------------------------------------- import

export function importSvg(text: string): ImportResult {
  const warnings: string[] = [];
  const warn = (w: string) => {
    if (!warnings.includes(w)) warnings.push(w);
  };
  const doc = new DOMParser().parseFromString(text, "image/svg+xml");
  const root = doc.documentElement;
  if (!root || root.localName !== "svg" || doc.getElementsByTagName("parsererror").length) {
    throw new Error("Not a valid SVG file.");
  }
  const sheet = parseStyleSheets(doc);
  const byId = new Map<string, Element>();
  for (const el of Array.from(doc.querySelectorAll("[id]"))) byId.set(el.getAttribute("id")!, el);
  const ref = (v: string | null | undefined): Element | null => {
    if (!v) return null;
    const m = v.match(/url\(\s*['"]?#([^'")\s]+)['"]?\s*\)/) || v.match(/^#(.+)$/);
    return m ? byId.get(m[1]) ?? null : null;
  };

  // viewBox -> the 3x3 stage centred on Flamey.
  let vb = (root.getAttribute("viewBox") || "").split(/[\s,]+/).map(Number);
  if (vb.length !== 4 || vb.some((v) => !Number.isFinite(v)) || vb[2] <= 0 || vb[3] <= 0) {
    const w = num(root.getAttribute("width") || undefined, 3);
    const h = num(root.getAttribute("height") || undefined, 3);
    vb = [0, 0, w, h];
    warn("No viewBox: assumed the whole canvas is the template's 3x3 stage.");
  }
  if (Math.abs(vb[2] / vb[3] - 1) > 0.01) warn("The viewBox is not square: draw on the template so units line up.");
  const rootM: M = [3 / vb[2], 0, 0, 3 / vb[3], -1.5 - (vb[0] * 3) / vb[2], -1.5 - (vb[1] * 3) / vb[3]];

  const ops: Op[] = [];
  const clips: Clip[] = [];
  const images: Record<string, string> = {};
  let allBounds: [number, number, number, number] | null = null;
  const grow = (b: [number, number, number, number] | null) => {
    if (!b) return;
    allBounds = allBounds
      ? [Math.min(allBounds[0], b[0]), Math.min(allBounds[1], b[1]), Math.max(allBounds[2], b[2]), Math.max(allBounds[3], b[3])]
      : b;
  };

  // ---- gradients
  function gradAttr(g: Element, name: string, seen = new Set<Element>()): string | null {
    const v = g.getAttribute(name);
    if (v !== null) return v;
    const href = g.getAttribute("href") || g.getAttributeNS("http://www.w3.org/1999/xlink", "href");
    const parent = ref(href);
    if (parent && !seen.has(parent)) {
      seen.add(parent);
      return gradAttr(parent, name, seen);
    }
    return null;
  }
  function gradStops(g: Element, seen = new Set<Element>()): Element[] {
    const own = Array.from(g.children).filter((c) => c.localName === "stop");
    if (own.length) return own;
    const href = g.getAttribute("href") || g.getAttributeNS("http://www.w3.org/1999/xlink", "href");
    const parent = ref(href);
    if (parent && !seen.has(parent)) {
      seen.add(parent);
      return gradStops(parent, seen);
    }
    return [];
  }
  const coord = (v: string | null, d: number, extent: number, obb: boolean) => {
    if (v === null) return d;
    if (v.trim().endsWith("%")) return (parseFloat(v) / 100) * (obb ? 1 : extent);
    return parseFloat(v);
  };

  /**
   * A gradient as a paint in ITS OWN space, plus the matrix from that space
   * to the element's user space (gradientTransform, and the bounding box for
   * objectBoundingBox).
   */
  function gradient(g: Element, bbox: [number, number, number, number] | null, alphaMul: number): { paint: GradientPaint; toUser: M } | null {
    const obb = (gradAttr(g, "gradientUnits") || "objectBoundingBox") === "objectBoundingBox";
    let toUser = parseTransform(gradAttr(g, "gradientTransform"));
    if (obb) {
      if (!bbox || bbox[2] - bbox[0] <= 0 || bbox[3] - bbox[1] <= 0) return null;
      toUser = mul([bbox[2] - bbox[0], 0, 0, bbox[3] - bbox[1], bbox[0], bbox[1]], toUser);
    }
    const spread = gradAttr(g, "spreadMethod");
    if (spread && spread !== "pad") warn(`spreadMethod="${spread}" is drawn as pad.`);
    const stops: Stop[] = [];
    let last = 0;
    for (const s of gradStops(g)) {
      const st = ownStyle(s, sheet);
      const off = s.getAttribute("offset") || "0";
      let t = off.trim().endsWith("%") ? parseFloat(off) / 100 : parseFloat(off);
      if (!Number.isFinite(t)) t = 0;
      t = Math.max(last, Math.min(1, t));
      last = t;
      const c = cssColour(st["stop-color"] || "black") || [0, 0, 0, 1];
      stops.push([Number(fmtNum(t, 5)), hex8(c, opacityVal(st["stop-opacity"]) * alphaMul)]);
    }
    if (!stops.length) return null;
    const ew = vb[2], eh = vb[3];
    if (g.localName === "linearGradient") {
      const x1 = coord(gradAttr(g, "x1"), 0, ew, obb);
      const y1 = coord(gradAttr(g, "y1"), 0, eh, obb);
      const x2 = coord(gradAttr(g, "x2"), obb ? 1 : ew, ew, obb);
      const y2 = coord(gradAttr(g, "y2"), 0, eh, obb);
      return { paint: { lin: [x1, y1, x2, y2], stops }, toUser };
    }
    const cx = coord(gradAttr(g, "cx"), obb ? 0.5 : ew / 2, ew, obb);
    const cy = coord(gradAttr(g, "cy"), obb ? 0.5 : eh / 2, eh, obb);
    const r = coord(gradAttr(g, "r"), obb ? 0.5 : Math.hypot(ew, eh) / Math.SQRT2 / 2, Math.hypot(ew, eh) / Math.SQRT2, obb);
    const fr = coord(gradAttr(g, "fr"), 0, Math.hypot(ew, eh) / Math.SQRT2, obb);
    const fx = gradAttr(g, "fx");
    const fy = gradAttr(g, "fy");
    if ((fx !== null && coord(fx, cx, ew, obb) !== cx) || (fy !== null && coord(fy, cy, eh, obb) !== cy)) {
      warn("A radial gradient's focal point (fx/fy) is drawn from its centre.");
    }
    return { paint: { rad: [cx, cy, fr, r], stops }, toUser };
  }

  /** Maps a gradient paint's coordinates through a similarity `m`. */
  function mapGradient(p: GradientPaint, m: M): GradientPaint {
    const r5 = (v: number) => Number(fmtNum(v, 5));
    if ("lin" in p) {
      const [a, b] = apply(m, p.lin[0], p.lin[1]);
      const [c, d] = apply(m, p.lin[2], p.lin[3]);
      return { lin: [r5(a), r5(b), r5(c), r5(d)], stops: p.stops };
    }
    if ("rad" in p) {
      const [a, b] = apply(m, p.rad[0], p.rad[1]);
      const s = scaleOf(m);
      return { rad: [r5(a), r5(b), r5(p.rad[2] * s), r5(p.rad[3] * s)], stops: p.stops };
    }
    return p;
  }

  // ---- clip paths (always in body units: the renderer clips before op.m)
  function clipFor(el: Element, userM: M, bbox: [number, number, number, number] | null): number | null {
    const cp = ref(ownStyle(el, sheet)["clip-path"]);
    if (!cp || cp.localName !== "clipPath") return null;
    let m = mul(userM, parseTransform(cp.getAttribute("transform")));
    if (cp.getAttribute("clipPathUnits") === "objectBoundingBox") {
      if (!bbox) return null;
      m = mul(m, [bbox[2] - bbox[0], 0, 0, bbox[3] - bbox[1], bbox[0], bbox[1]]);
    }
    const all: Seg[] = [];
    let eo = false;
    const walk = (node: Element, nm: M) => {
      for (const ch of Array.from(node.children)) {
        const cm = mul(nm, parseTransform(ch.getAttribute("transform")));
        if (ch.localName === "use") {
          const target = ref(ch.getAttribute("href") || ch.getAttributeNS("http://www.w3.org/1999/xlink", "href"));
          if (target) {
            const um = mul(cm, [1, 0, 0, 1, num(ch.getAttribute("x") || undefined, 0), num(ch.getAttribute("y") || undefined, 0)]);
            const g = shapeSegs(target);
            if (g) all.push(...transformSegs(g, mul(um, parseTransform(target.getAttribute("transform")))));
          }
          continue;
        }
        if (ch.localName === "g") {
          walk(ch, cm);
          continue;
        }
        const segs = shapeSegs(ch);
        if (segs) {
          all.push(...transformSegs(segs, cm));
          if ((ownStyle(ch, sheet)["clip-rule"] || "") === "evenodd") eo = true;
        } else if (ch.localName === "text") warn("Text inside a clip-path is ignored.");
      }
    };
    walk(cp, m);
    if (!all.length) return null;
    const d = segsToD(all);
    const existing = clips.findIndex((c) => c.d === d && !!c.eo === eo);
    if (existing >= 0) return existing;
    clips.push(eo ? { d, eo: true } : { d });
    return clips.length - 1;
  }

  function shapeSegs(el: Element): Seg[] | null {
    const a = (k: string, d = 0) => num(el.getAttribute(k) || undefined, d);
    const pc = (k: string, ext: number) => {
      const v = el.getAttribute(k);
      if (v && v.trim().endsWith("%")) return (parseFloat(v) / 100) * ext;
      return a(k);
    };
    switch (el.localName) {
      case "path":
        return normalizePath(el.getAttribute("d") || "");
      case "rect": {
        const w = pc("width", vb[2]);
        const h = pc("height", vb[3]);
        if (w <= 0 || h <= 0) return null;
        let rx = el.getAttribute("rx");
        let ry = el.getAttribute("ry");
        if (rx === null || rx === "auto") rx = ry;
        if (ry === null || ry === "auto") ry = rx;
        return rectSegs(pc("x", vb[2]), pc("y", vb[3]), w, h, num(rx || undefined, 0), num(ry || undefined, 0));
      }
      case "circle": {
        const r = a("r");
        return r > 0 ? ellipseSegs(a("cx"), a("cy"), r, r) : null;
      }
      case "ellipse": {
        const rx = a("rx");
        const ry = a("ry");
        return rx > 0 && ry > 0 ? ellipseSegs(a("cx"), a("cy"), rx, ry) : null;
      }
      case "line":
        return [
          { c: "M", p: [a("x1"), a("y1")] },
          { c: "L", p: [a("x2"), a("y2")] },
        ];
      case "polyline":
        return pointsSegs(el.getAttribute("points") || "", false);
      case "polygon":
        return pointsSegs(el.getAttribute("points") || "", true);
    }
    return null;
  }

  function paintFor(
    v: string | undefined,
    colourAttr: string | undefined,
    alpha: number,
    bbox: [number, number, number, number] | null,
  ): { kind: "solid"; paint: Colour } | { kind: "grad"; paint: GradientPaint; toUser: M } | null {
    if (!v || v === "none" || v === "transparent") return null;
    if (v.startsWith("url(")) {
      const g = ref(v);
      if (g && (g.localName === "linearGradient" || g.localName === "radialGradient")) {
        const gr = gradient(g, bbox, alpha);
        if (gr) return { kind: "grad", paint: gr.paint, toUser: gr.toUser };
        warn("A gradient with no stops (or an empty box) was skipped.");
        return null;
      }
      if (g && g.localName === "pattern") warn("Pattern fills aren't supported; skipped.");
      // url(#x) fallback colour: "url(#g) red"
      const fb = v.replace(/url\([^)]*\)/, "").trim();
      if (!fb) return null;
      v = fb;
    }
    if (v === "currentColor") v = colourAttr || "black";
    const c = cssColour(v);
    if (!c) {
      warn(`Unknown colour "${v}" skipped.`);
      return null;
    }
    return { kind: "solid", paint: hex8(c, alpha) };
  }

  const r5m = (m: M): Matrix => m.map((v) => Number(fmtNum(v, 5))) as Matrix;

  function emit(el: Element, segs: Seg[], userM: M, style: Style, opacity: number, clipIds: number[]) {
    if (!segs.length) return;
    const bboxLocal = segBounds(segs);
    const ownClip = clipFor(el, userM, bboxLocal);
    const clip = ownClip === null ? clipIds : [...clipIds, ownClip];
    const isLine = el.localName === "line" || el.localName === "polyline";
    const fill = isLine ? null : paintFor(style.fill ?? "black", style.color, opacityVal(style["fill-opacity"]), bboxLocal);
    const stroke = paintFor(style.stroke, style.color, opacityVal(style["stroke-opacity"]), bboxLocal);
    const base = (o: Record<string, unknown>) => {
      if (opacity < 1) o.a = Number(fmtNum(opacity, 4));
      if (clip.length) o.clip = clip;
      return o;
    };
    grow(segBounds(transformSegs(segs, userM)));

    if (fill) {
      const eo = style["fill-rule"] === "evenodd";
      if (fill.kind === "solid") {
        ops.push(base({ op: "fill", d: segsToD(transformSegs(segs, userM)), paint: fill.paint, ...(eo ? { eo: true } : {}) }) as Op);
      } else {
        const toBody = mul(userM, fill.toUser);
        if (isSimilarity(toBody)) {
          ops.push(base({ op: "fill", d: segsToD(transformSegs(segs, userM)), paint: mapGradient(fill.paint, toBody), ...(eo ? { eo: true } : {}) }) as Op);
        } else {
          // Local = the gradient's own space; "m" carries it to body units.
          const local = transformSegs(segs, inv(fill.toUser));
          ops.push(base({ op: "fill", d: segsToD(local), paint: roundGrad(fill.paint), m: r5m(toBody), ...(eo ? { eo: true } : {}) }) as Op);
        }
      }
    }
    if (stroke) {
      const sw = num(style["stroke-width"], 1);
      if (sw > 0) {
        const extra: Record<string, unknown> = {};
        const cap = style["stroke-linecap"];
        if (cap === "round" || cap === "square") extra.cap = cap;
        const join = style["stroke-linejoin"];
        if (join === "round" || join === "bevel") extra.join = join;
        else if (join && join !== "miter") warn(`stroke-linejoin="${join}" is drawn as miter.`);
        const miter = num(style["stroke-miterlimit"], 4);
        const dashRaw = style["stroke-dasharray"];
        let dash = dashRaw && dashRaw !== "none" ? (dashRaw.match(/[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g) || []).map(Number) : [];
        if (dash.length % 2 === 1) dash = [...dash, ...dash];
        const phase = num(style["stroke-dashoffset"], 0);

        const gradM = stroke.kind === "grad" ? mul(userM, stroke.toUser) : null;
        const bake = isSimilarity(userM) && (!gradM || isSimilarity(gradM));
        if (bake) {
          const s = scaleOf(userM);
          extra.miter = miter;
          if (dash.length) extra.dash = dash.map((v) => Number(fmtNum(v * s, 5)));
          if (phase) extra.phase = Number(fmtNum(phase * s, 5));
          const paint: Paint = stroke.kind === "solid" ? stroke.paint : mapGradient(stroke.paint, gradM!);
          ops.push(base({ op: "stroke", d: segsToD(transformSegs(segs, userM)), paint, w: Number(fmtNum(sw * s, 5)), ...cleanMiter(extra) }) as Op);
        } else if (stroke.kind === "solid" || !gradM || isSimilarity(stroke.toUser)) {
          // Local = the element's user space (strokes stretch with it, as in SVG).
          extra.miter = miter;
          if (dash.length) extra.dash = dash;
          if (phase) extra.phase = phase;
          const paint: Paint = stroke.kind === "solid" ? stroke.paint : mapGradient(stroke.paint, stroke.toUser);
          ops.push(base({ op: "stroke", d: segsToD(segs), paint, w: Number(fmtNum(sw, 5)), m: r5m(userM), ...cleanMiter(extra) }) as Op);
        } else {
          // A gradient skewed by its own box: local = gradient space.
          const k = scaleOf(stroke.toUser) || 1;
          extra.miter = miter;
          if (dash.length) extra.dash = dash.map((v) => Number(fmtNum(v / k, 5)));
          if (phase) extra.phase = Number(fmtNum(phase / k, 5));
          warn("A stroke whose gradient is stretched by its bounding box is approximated.");
          ops.push(base({ op: "stroke", d: segsToD(transformSegs(segs, inv(stroke.toUser))), paint: roundGrad(stroke.paint), w: Number(fmtNum(sw / k, 5)), m: r5m(gradM), ...cleanMiter(extra) }) as Op);
        }
      }
    }
  }

  function roundGrad(p: GradientPaint): GradientPaint {
    const r5 = (v: number) => Number(fmtNum(v, 5));
    if ("lin" in p) return { lin: p.lin.map(r5) as [number, number, number, number], stops: p.stops };
    if ("rad" in p) return { rad: p.rad.map(r5) as [number, number, number, number], stops: p.stops };
    return p;
  }
  function cleanMiter(extra: Record<string, unknown>) {
    // The renderer's default miter limit is 10; SVG's is 4 — only write it when it's a mitred stroke.
    if (extra.join === "round" || extra.join === "bevel") delete extra.miter;
    return extra;
  }

  let imageCount = 0;
  function walk(el: Element, parentM: M, inherited: Style, opacity: number, clipIds: number[]) {
    const id = el.getAttribute("id") || "";
    if (IGNORED_IDS.includes(id)) return;
    const tag = el.localName;
    if (["defs", "clipPath", "mask", "linearGradient", "radialGradient", "pattern", "symbol", "style", "title", "desc", "metadata", "marker", "filter"].includes(tag)) return;
    if (el.getAttribute("inkscape:groupmode") === "layer" && /^(guides?|reference)$/i.test(el.getAttribute("inkscape:label") || "")) return;
    const own = ownStyle(el, sheet);
    if (own.display === "none") return;
    const style: Style = {};
    for (const [k, v] of Object.entries(inherited)) if (INHERITED.has(k)) style[k] = v;
    for (const [k, v] of Object.entries(own)) if (v !== "inherit") style[k] = v;
    if (style.visibility === "hidden" && tag !== "g") return;
    const m = tag === "svg" && el !== root ? parentM : mul(parentM, parseTransform(el.getAttribute("transform")));
    const op = opacity * opacityVal(own.opacity);
    if (own.mask) warn("Masks aren't supported; the masked art is drawn unmasked.");
    if (own.filter) warn("SVG filters aren't supported (use a skin's fx by hand).");

    if (tag === "g" || tag === "svg" || tag === "a" || tag === "switch") {
      const gClip = el === root ? null : clipFor(el, m, null);
      const ids = gClip === null ? clipIds : [...clipIds, gClip];
      for (const ch of Array.from(el.children)) walk(ch, m, style, op, ids);
      return;
    }
    if (tag === "use") {
      const target = ref(el.getAttribute("href") || el.getAttributeNS("http://www.w3.org/1999/xlink", "href"));
      if (target) {
        const um = mul(m, [1, 0, 0, 1, num(el.getAttribute("x") || undefined, 0), num(el.getAttribute("y") || undefined, 0)]);
        if (target.localName === "symbol") for (const ch of Array.from(target.children)) walk(ch, um, style, op, clipIds);
        else walk(target, um, style, op, clipIds);
      }
      return;
    }
    if (tag === "text" || tag === "tspan") {
      warn("Text is ignored: convert text to outlines (paths) before exporting.");
      return;
    }
    if (tag === "image") {
      const href = el.getAttribute("href") || el.getAttributeNS("http://www.w3.org/1999/xlink", "href") || "";
      if (!href.startsWith("data:image/")) {
        warn("Linked (non-embedded) images are skipped: embed them.");
        return;
      }
      const key = `img${imageCount++}`;
      images[key] = href;
      const a = (k: string) => num(el.getAttribute(k) || undefined, 0);
      const o: Record<string, unknown> = { op: "image", src: key, rect: [a("x"), a("y"), a("width"), a("height")].map((v) => Number(fmtNum(v, 5))), m: r5m(m) };
      if (op < 1) o.a = Number(fmtNum(op, 4));
      if (clipIds.length) o.clip = clipIds;
      ops.push(o as Op);
      return;
    }
    const segs = shapeSegs(el);
    if (segs) emit(el, segs, m, style, op, clipIds);
    else if (tag !== "svg") warn(`<${tag}> isn't supported and was skipped.`);
  }

  walk(root, rootM, {}, 1, []);
  if (!ops.length) warn("Nothing drawable found outside the template's guide layers.");
  const recording: Recording = { ops };
  if (clips.length) recording.clips = clips;
  if (Object.keys(images).length) recording.images = images;
  return { recording, warnings, bounds: allBounds };
}
