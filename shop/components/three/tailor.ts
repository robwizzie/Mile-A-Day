// Cuts a 3D garment from its flat artwork, the way a pattern becomes a shirt.
//
// The print images are flat lays: the front panel as seen from the front,
// the back panel as seen from behind. Each piece is built from real parts —
//
//   torso   an oval body whose depth tapers to nothing at the shoulder seam
//           (so it drapes from the hanger), with an open neckline: the back
//           neck sits higher than the front, like a real collar;
//   sleeves tubes from armhole to cuff, the print side turned toward the
//           outside of the arm, so a side view shows the sleeve design;
//   hood    on the hoodie, the torso's top continues up into a dome.
//
// Every surface point keeps the flat-lay coordinate it came from, and that is
// its texture coordinate: the front print wraps around the chest exactly as
// fabric would (compressing toward the side seams, never stretching), the back
// print around the back, and the side seams fall where the flat edges were.

import * as THREE from "three";

/** Points are in the art's own box: x and y from 0 to 1, y down. */
type Pt = [number, number];

export type Cut = {
  /** Torso centre line. */
  cx: number;
  /** Where the torso becomes a closed tube (the armpit). */
  armY: number;
  /** Torso depth ÷ width once fully round. */
  depth: number;
  /** Right sleeve (the left mirrors it): shoulder point, armpit, cuff outer, cuff inner. */
  sleeve?: { shoulder: Pt; pit: Pt; cuffOut: Pt; cuffIn: Pt; depth: number };
  /** Hoodie: the hood is the torso's top, not a neckline. */
  hood?: boolean;
};

export const CUTS = {
  tee: {
    cx: 0.5,
    armY: 0.318,
    depth: 0.5,
    sleeve: { shoulder: [0.806, 0.1], pit: [0.795, 0.318], cuffOut: [0.993, 0.347], cuffIn: [0.85, 0.403], depth: 0.62 },
  },
  longsleeve: {
    cx: 0.5,
    armY: 0.341,
    depth: 0.5,
    sleeve: { shoulder: [0.806, 0.1], pit: [0.795, 0.341], cuffOut: [0.983, 0.889], cuffIn: [0.881, 0.907], depth: 0.85 },
  },
  tank: { cx: 0.5, armY: 0.323, depth: 0.46 },
  hoodie: {
    cx: 0.5,
    armY: 0.7,
    depth: 0.56,
    hood: true,
    sleeve: { shoulder: [0.772, 0.356], pit: [0.775, 0.7], cuffOut: [0.993, 0.848], cuffIn: [0.924, 0.893], depth: 0.85 },
  },
} satisfies Record<string, Cut>;

export type Part = { geometry: THREE.BufferGeometry; side: "front" | "back" };
export type Tailored = {
  parts: Part[];
  /** Hanger placement, in garment units (height 1, y up, 0 = top of the box). */
  hanger: { centerY: number; shoulderY: number; halfWidth: number };
};

const RAMP = 0.15; // how far below the shoulder seam the body is fully round
const MIN_HALF = 0.016; // never thinner than the hanger inside
const SLEEVE_TURN = 0.38; // radians the sleeve print turns toward the outside

/** Quarter perimeter of an ellipse with semi-axes 1 and r (Ramanujan). */
const quarter = (r: number) => (Math.PI / 4) * (3 * (1 + r) - Math.sqrt((3 + r) * (1 + 3 * r)));

/**
 * Where a point `s` of the way from the centre to the seam (−1…1, measured
 * along the fabric) lands on an ellipse of depth ratio r: returns the angle φ
 * with x = sin φ, z = r·cos φ. Arc length, not angle — on a flattened oval
 * most of the fabric faces forward, so a chest print stays on the chest.
 */
function wrapper(r: number) {
  const N = 256;
  const len = new Float32Array(N + 1);
  for (let i = 1; i <= N; i++) {
    const a = ((i - 0.5) / N) * (Math.PI / 2);
    len[i] = len[i - 1] + Math.hypot(Math.cos(a), r * Math.sin(a)) * (Math.PI / 2 / N);
  }
  const total = len[N];
  return (s: number) => {
    const target = Math.min(1, Math.abs(s)) * total;
    let lo = 0;
    let hi = N;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (len[mid] < target) lo = mid;
      else hi = mid;
    }
    const f = (target - len[lo]) / Math.max(1e-9, len[hi] - len[lo]);
    return Math.sign(s) * ((lo + f) / N) * (Math.PI / 2);
  };
}

const smooth = (e0: number, e1: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0)));
  return t * t * (3 - 2 * t);
};

export function tailor(front: HTMLImageElement, cut: Cut): Tailored {
  const aspect = front.naturalWidth / front.naturalHeight;

  // ── Read the outline ────────────────────────────────────────────────────
  const MW = 320;
  const MH = Math.round(MW / aspect);
  const c = document.createElement("canvas");
  c.width = MW;
  c.height = MH;
  const ctx = c.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(front, 0, 0, MW, MH);
  const px = ctx.getImageData(0, 0, MW, MH).data;
  const solid = (x: number, y: number) => px[(y * MW + x) * 4 + 3] > 140;

  const col = (xn: number) => Math.max(0, Math.min(MW - 1, Math.round(xn * (MW - 1))));
  const row = (yn: number) => Math.max(0, Math.min(MH - 1, Math.round(yn * (MH - 1))));
  const topAt = (xn: number) => {
    const x = col(xn);
    for (let y = 0; y < MH; y++) if (solid(x, y)) return y / (MH - 1);
    return 0;
  };
  const bottomAt = (xn: number) => {
    const x = col(xn);
    for (let y = MH - 1; y >= 0; y--) if (solid(x, y)) return y / (MH - 1);
    return 1;
  };
  /** Half-width of the torso (the run of fabric through the centre line). */
  const rawHalf = (yn: number) => {
    const y = row(yn);
    const c0 = col(cut.cx);
    let l = c0;
    let r = c0;
    while (l > 0 && solid(l - 1, y)) l--;
    while (r < MW - 1 && solid(r + 1, y)) r++;
    return (r - l) / 2 / (MW - 1);
  };
  const armHalf = rawHalf(cut.armY + 0.05);
  // Below the armpit the torso is measured row by row (a hoodie's hem band
  // narrows); right at the armpit the run still includes the sleeves, so it
  // eases in from the armpit width and never balloons past it.
  // Measure no lower than just above the hem, where a curved hem would read narrow.
  const hemSafe = bottomAt(cut.cx + armHalf * 0.85) - 0.03;
  const halfAt = (yn: number) => {
    if (yn <= cut.armY) return armHalf;
    let s = 0;
    for (let k = -2; k <= 2; k++) s += Math.min(rawHalf(Math.min(hemSafe, yn + 0.05 + k * 0.006)), armHalf * 1.04);
    const below = s / 5;
    return armHalf + (below - armHalf) * smooth(cut.armY, cut.armY + 0.08, yn);
  };

  // Neckline: the lowest point of the shoulder line near the centre is the
  // collar's edge; the back neck rises most of the way back up to it.
  let neckTop = 1;
  let neckHalf = 0;
  if (!cut.hood) {
    for (let k = 0; k <= 60; k++) {
      const dx = (k / 60) * armHalf * 0.8;
      const t = topAt(cut.cx + dx);
      if (t < neckTop - 1e-4) {
        neckTop = t;
        neckHalf = dx;
      }
    }
  }
  const frontTop = topAt;
  const backTop = (xn: number) => {
    const t = topAt(xn);
    if (cut.hood || Math.abs(xn - cut.cx) >= neckHalf) return t;
    return neckTop + (t - neckTop) * 0.3;
  };

  const W = (xn: number) => (xn - cut.cx) * aspect; // flat x → world
  const parts: Part[] = [];

  // ── Torso ──────────────────────────────────────────────────────────────
  const qT = quarter(cut.depth);
  const wrapT = wrapper(cut.depth);
  const torso = (side: "front" | "back") => {
    const NS = 72;
    const NT = 96;
    const sign = side === "front" ? 1 : -1;
    const top = side === "front" ? frontTop : backTop;
    const pos: number[] = [];
    const uv: number[] = [];
    for (let i = 0; i <= NS; i++) {
      const s = -1 + (2 * i) / NS;
      const xTop = cut.cx + s * armHalf * 0.995;
      const y0 = top(xTop);
      const y1 = bottomAt(cut.cx + s * halfAt(0.97) * 0.99);
      for (let j = 0; j <= NT; j++) {
        const t = j / NT;
        const y = y0 + (y1 - y0) * Math.pow(t, 1.25);
        const half = halfAt(y);
        const xf = cut.cx + s * half;
        // How deep the body is here: flat at the shoulder seam, round below.
        const f = smooth(0, RAMP, y - y0);
        const A = (half * aspect) / qT;
        const phi = wrapT(s);
        const X = A * Math.sin(phi);
        let Z = Math.max(f * cut.depth * A, MIN_HALF) * Math.cos(phi);
        Z = sign * Z - 0.05 * X * X;
        pos.push(X, -y, Z);
        uv.push(side === "front" ? xf : 1 - xf, 1 - y);
      }
    }
    const idx: number[] = [];
    const at = (i: number, j: number) => i * (NT + 1) + j;
    for (let i = 0; i < NS; i++)
      for (let j = 0; j < NT; j++) {
        const a = at(i, j);
        const b = at(i + 1, j);
        const cc = at(i, j + 1);
        const d = at(i + 1, j + 1);
        if (side === "front") idx.push(a, cc, b, b, cc, d);
        else idx.push(a, b, cc, b, d, cc);
      }
    parts.push({ geometry: build(pos, uv, idx), side });
  };
  torso("front");
  torso("back");

  // ── Sleeves ────────────────────────────────────────────────────────────
  if (cut.sleeve) {
    const sl = cut.sleeve;
    const qS = quarter(sl.depth);
    const wrapS = wrapper(sl.depth);
    // The torso is narrower round than flat; the sleeves move in with it.
    const shrink = armHalf * aspect * (1 - 1 / qT);
    for (const hand of [1, -1]) {
      const m = (p: Pt): Pt => (hand === 1 ? p : [2 * cut.cx - p[0], p[1]]);
      const P0 = m(sl.shoulder);
      const P1 = m(sl.pit);
      const Q0 = m(sl.cuffOut);
      const Q1 = m(sl.cuffIn);
      for (const side of ["front", "back"] as const) {
        const NA = 40;
        const NP = 28;
        const pos: number[] = [];
        const uv: number[] = [];
        for (let i = 0; i <= NA; i++) {
          const a = i / NA;
          const E0: Pt = [P0[0] + (Q0[0] - P0[0]) * a, P0[1] + (Q0[1] - P0[1]) * a];
          const E1: Pt = [P1[0] + (Q1[0] - P1[0]) * a, P1[1] + (Q1[1] - P1[1]) * a];
          const mid: Pt = [(E0[0] + E1[0]) / 2, (E0[1] + E1[1]) / 2];
          const ex = W(E0[0]) - W(E1[0]);
          const ey = -E0[1] + E1[1];
          const len = Math.hypot(ex, ey);
          const nx = ex / len;
          const ny = ey / len;
          const A = len / 2 / qS;
          const depth = sl.depth * A * (0.55 + 0.45 * smooth(0, 0.3, a));
          const cxw = W(mid[0]) - hand * shrink;
          const cyw = -mid[1];
          for (let k = 0; k <= NP; k++) {
            const u = k / NP;
            // Front panel: outer seam → inner seam; back panel: inner → outer.
            const s = side === "front" ? -1 + 2 * u : 1 - 2 * u; // −1 outer edge, +1 inner
            const w = wrapS(-1 + 2 * u);
            const phi = (side === "front" ? w : Math.PI + w) - SLEEVE_TURN;
            const across = -A * Math.sin(phi);
            const X = cxw + nx * across;
            const Y = cyw + ny * across;
            const Z = depth * Math.cos(phi) - 0.05 * X * X;
            pos.push(X, Y, Z);
            const fx = E0[0] + (E1[0] - E0[0]) * ((s + 1) / 2);
            const fy = E0[1] + (E1[1] - E0[1]) * ((s + 1) / 2);
            uv.push(side === "front" ? fx : 1 - fx, 1 - fy);
          }
        }
        const idx: number[] = [];
        const at = (i: number, k: number) => i * (NP + 1) + k;
        for (let i = 0; i < NA; i++)
          for (let k = 0; k < NP; k++) idx.push(at(i, k), at(i + 1, k), at(i, k + 1), at(i, k + 1), at(i + 1, k), at(i + 1, k + 1));
        const g = build(pos, uv, idx);
        orientOutward(g);
        parts.push({ geometry: g, side });
      }
    }
  }

  const shoulderY = topAt(cut.cx + armHalf * 0.7);
  return {
    parts,
    hanger: {
      centerY: -(cut.hood ? shoulderY - 0.03 : neckTop + 0.02),
      shoulderY: -(shoulderY + 0.06),
      halfWidth: (armHalf * aspect * 0.62) / qT,
    },
  };
}

function build(pos: number[], uv: number[], idx: number[]) {
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

/** Flip a tube's winding if its normals point inward. */
function orientOutward(g: THREE.BufferGeometry) {
  const p = g.getAttribute("position");
  const n = g.getAttribute("normal");
  const center = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) center.add(new THREE.Vector3().fromBufferAttribute(p, i));
  center.divideScalar(p.count);
  let score = 0;
  const v = new THREE.Vector3();
  const nn = new THREE.Vector3();
  for (let i = 0; i < p.count; i += 7) {
    v.fromBufferAttribute(p, i).sub(center);
    nn.fromBufferAttribute(n, i);
    score += v.dot(nn);
  }
  if (score >= 0) return;
  const index = g.getIndex()!;
  const arr = index.array as Uint32Array | Uint16Array;
  for (let i = 0; i < arr.length; i += 3) {
    const t = arr[i + 1];
    arr[i + 1] = arr[i + 2];
    arr[i + 2] = t;
  }
  index.needsUpdate = true;
  g.computeVertexNormals();
}
