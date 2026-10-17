// A garment as it actually hangs: two layers of fabric, front and back, cut
// to the piece's exact outline and sewn at the edge.
//
// A shirt on a hanger is nearly flat — what makes it read as real is a crisp
// seam at the edge, a little volume where the hanger holds the shoulders,
// soft folds that deepen toward the hem, and sleeves that fall slightly back
// from the body. The outline comes from the print itself (so a side view is a
// thin, wavy edge, the way a hung garment looks side-on), and each layer
// wears its own print: front on the front, back on the back.

import * as THREE from "three";

/** A cut's landmarks in its art box (x and y from 0 to 1, y down). */
export type Cut = {
  /** Centre line of the body. */
  cx: number;
  /** The armpit: below it the body's width is the body alone. */
  armY: number;
  /** Hoodie: the top of the outline is the hood, not a neckline. */
  hood?: boolean;
};

export const CUTS = {
  tee: { cx: 0.5, armY: 0.318 },
  longsleeve: { cx: 0.5, armY: 0.341 },
  tank: { cx: 0.5, armY: 0.323 },
  hoodie: { cx: 0.5, armY: 0.7, hood: true },
} satisfies Record<string, Cut>;

export type Part = { geometry: THREE.BufferGeometry; side: "front" | "back" };
export type Tailored = {
  parts: Part[];
  /** Hanger placement, in garment units (height 1, y up, 0 = top of the box). */
  hanger: { centerY: number; shoulderY: number; halfWidth: number };
};

const smooth = (e0: number, e1: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0)));
  return t * t * (3 - 2 * t);
};

export type Fabric = {
  /** Half-thickness of the body (fraction of height). */
  body: number;
  /** Extra half-thickness at the shoulders, where the hanger is inside. */
  shoulders: number;
  /** Fold depth at the hem. */
  folds: number;
};

export function drape(front: HTMLImageElement, cut: Cut, fabric: Fabric, alphaCut: number): Tailored {
  const aspect = front.naturalWidth / front.naturalHeight;

  // ── Outline ────────────────────────────────────────────────────────────
  const MW = 300;
  const MH = Math.round(MW / aspect);
  const c = document.createElement("canvas");
  c.width = MW;
  c.height = MH;
  const ctx = c.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(front, 0, 0, MW, MH);
  const raw = ctx.getImageData(0, 0, MW, MH).data;
  const A = new Float32Array(MW * MH);
  for (let i = 0; i < A.length; i++) A[i] = raw[i * 4 + 3] / 255;
  const sample = (field: Float32Array, x: number, y: number) => {
    x = Math.max(0, Math.min(MW - 1.001, x));
    y = Math.max(0, Math.min(MH - 1.001, y));
    const x0 = Math.floor(x);
    const y0 = Math.floor(y);
    const fx = x - x0;
    const fy = y - y0;
    const i = y0 * MW + x0;
    return field[i] * (1 - fx) * (1 - fy) + field[i + 1] * fx * (1 - fy) + field[i + MW] * (1 - fx) * fy + field[i + MW + 1] * fx * fy;
  };
  const solid = (xn: number, yn: number) => sample(A, xn * (MW - 1), yn * (MH - 1)) >= alphaCut;
  const topAt = (xn: number) => {
    for (let y = 0; y < MH; y++) if (solid(xn, y / (MH - 1))) return y / (MH - 1);
    return 0;
  };
  const bottomAt = (xn: number) => {
    for (let y = MH - 1; y >= 0; y--) if (solid(xn, y / (MH - 1))) return y / (MH - 1);
    return 1;
  };
  const halfRun = (yn: number) => {
    let l = cut.cx;
    let r = cut.cx;
    while (l > 0 && solid(l - 1 / MW, yn)) l -= 1 / MW;
    while (r < 1 && solid(r + 1 / MW, yn)) r += 1 / MW;
    return (r - l) / 2;
  };
  const torsoHalf = halfRun(cut.armY + 0.06); // flat units
  const hem = bottomAt(cut.cx + torsoHalf * 0.8);
  const shoulderY = topAt(cut.cx + torsoHalf * 0.7);

  // Distance to the edge (chamfer), in px of the mask.
  const D = new Float32Array(MW * MH);
  for (let i = 0; i < D.length; i++) D[i] = A[i] >= alphaCut ? 1e6 : 0;
  const R2 = Math.SQRT2;
  for (let y = 0; y < MH; y++)
    for (let x = 0; x < MW; x++) {
      const i = y * MW + x;
      if (!D[i]) continue;
      let d = D[i];
      if (x > 0) d = Math.min(d, D[i - 1] + 1);
      if (y > 0) {
        d = Math.min(d, D[i - MW] + 1);
        if (x > 0) d = Math.min(d, D[i - MW - 1] + R2);
        if (x < MW - 1) d = Math.min(d, D[i - MW + 1] + R2);
      }
      D[i] = d;
    }
  for (let y = MH - 1; y >= 0; y--)
    for (let x = MW - 1; x >= 0; x--) {
      const i = y * MW + x;
      if (!D[i]) continue;
      let d = D[i];
      if (x < MW - 1) d = Math.min(d, D[i + 1] + 1);
      if (y < MH - 1) {
        d = Math.min(d, D[i + MW] + 1);
        if (x < MW - 1) d = Math.min(d, D[i + MW + 1] + R2);
        if (x > 0) d = Math.min(d, D[i + MW - 1] + R2);
      }
      D[i] = d;
    }

  // ── Grid, snapped to the outline ───────────────────────────────────────
  const C = 140;
  const R = Math.round(C / aspect);
  const N = (C + 1) * (R + 1);
  const mx = new Float32Array(N);
  const my = new Float32Array(N);
  const state = new Uint8Array(N); // 0 out, 1 edge, 2 inside
  const idx = (i: number, j: number) => j * (C + 1) + i;
  for (let j = 0; j <= R; j++)
    for (let i = 0; i <= C; i++) {
      const k = idx(i, j);
      mx[k] = (i / C) * (MW - 1);
      my[k] = (j / R) * (MH - 1);
      state[k] = sample(A, mx[k], my[k]) >= alphaCut ? 2 : 0;
    }
  for (let j = 0; j <= R; j++)
    for (let i = 0; i <= C; i++) {
      const k = idx(i, j);
      if (state[k] === 2) continue;
      let sx = 0;
      let sy = 0;
      let n = 0;
      for (let dj = -1; dj <= 1; dj++)
        for (let di = -1; di <= 1; di++) {
          if (!di && !dj) continue;
          const ii = i + di;
          const jj = j + dj;
          if (ii < 0 || jj < 0 || ii > C || jj > R) continue;
          const kk = idx(ii, jj);
          if (state[kk] !== 2) continue;
          let lo = 0;
          let hi = 1;
          for (let s = 0; s < 8; s++) {
            const t = (lo + hi) / 2;
            if (sample(A, mx[k] + (mx[kk] - mx[k]) * t, my[k] + (my[kk] - my[k]) * t) >= alphaCut) hi = t;
            else lo = t;
          }
          const t = (lo + hi) / 2;
          sx += mx[k] + (mx[kk] - mx[k]) * t;
          sy += my[k] + (my[kk] - my[k]) * t;
          n++;
        }
      if (n) {
        state[k] = 1;
        mx[k] = sx / n;
        my[k] = sy / n;
      }
    }

  // ── Shape ─────────────────────────────────────────────────────────────
  const torsoW = torsoHalf * aspect; // world half-width of the body
  const EDGE = 0.014; // the seam: crisp, not puffy
  const front3 = new Float32Array(N * 3);
  const back3 = new Float32Array(N * 3);
  const uvF = new Float32Array(N * 2);
  const uvB = new Float32Array(N * 2);
  for (let k = 0; k < N; k++) {
    if (!state[k]) continue;
    const xn = mx[k] / (MW - 1);
    const yn = my[k] / (MH - 1);
    const X = (xn - cut.cx) * aspect;
    const Y = -yn;
    const d = state[k] === 2 ? sample(D, mx[k], my[k]) / (MH - 1) : 0;
    const out = Math.max(0, Math.abs(X) - torsoW); // how far into a sleeve
    const inBody = 1 - smooth(0, 0.06, out);

    // Thickness: thin cloth, fuller over the hanger and through the chest.
    const seam = Math.sqrt(Math.min(d / EDGE, 1) * (2 - Math.min(d / EDGE, 1)));
    const hangerBulge = fabric.shoulders * Math.exp(-(((yn - shoulderY - 0.06) / 0.11) ** 2)) * inBody;
    const chest = 0.012 * smooth(0.02, 0.2, d) * inBody;
    const half = (fabric.body + hangerBulge + chest) * seam;

    // Folds: nothing at the shoulders, deepening toward the hem.
    const fall = smooth(shoulderY + 0.05, hem, yn);
    const sleeveFall = smooth(0, 0.25, out);
    const amp = fabric.folds * Math.max(fall * inBody, sleeveFall * 0.6);
    let F =
      amp *
      (0.62 * Math.sin((X / 0.31) * Math.PI * 2 + 1.7 + 1.1 * yn) +
        0.38 * Math.sin((X / 0.15) * Math.PI * 2 + 0.4 - 1.6 * yn));
    F += 0.35 * fabric.folds * smooth(hem - 0.12, hem, yn) * inBody * Math.sin((X / 0.09) * Math.PI * 2 + 2.1);

    // The hanger is curved, the sleeves fall back from the shoulders.
    const curve = -0.07 * X * X;
    const sleeveBack = -0.3 * out * smooth(0, 0.08, out);

    const z0 = F + curve + sleeveBack;
    front3.set([X, Y, z0 + half], k * 3);
    back3.set([X, Y, z0 - half], k * 3);
    uvF.set([xn, 1 - yn], k * 2);
    uvB.set([1 - xn, 1 - yn], k * 2);
  }

  const fIdx: number[] = [];
  const bIdx: number[] = [];
  const tri = (a: number, b: number, cc: number) => {
    if (!state[a] || !state[b] || !state[cc]) return;
    if (state[a] !== 2 && state[b] !== 2 && state[cc] !== 2) return;
    const cx = (mx[a] + mx[b] + mx[cc]) / 3;
    const cy = (my[a] + my[b] + my[cc]) / 3;
    if (sample(A, cx, cy) < alphaCut * 0.7) return;
    fIdx.push(a, b, cc);
    bIdx.push(a, cc, b);
  };
  for (let j = 0; j < R; j++)
    for (let i = 0; i < C; i++) {
      const a = idx(i, j);
      const b = idx(i + 1, j);
      const c2 = idx(i, j + 1);
      const d = idx(i + 1, j + 1);
      tri(a, c2, b);
      tri(b, c2, d);
    }

  const geo = (pos: Float32Array, uv: Float32Array, index: number[]) => {
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    g.setAttribute("uv", new THREE.BufferAttribute(uv, 2));
    g.setIndex(index);
    g.computeVertexNormals();
    return g;
  };
  const parts: Part[] = [
    { geometry: geo(front3, uvF, fIdx), side: "front" },
    { geometry: geo(back3, uvB, bIdx), side: "back" },
  ];

  // Hanger: neck where the collar is lowest (or the hood's shoulders).
  let neckTop = 1;
  if (!cut.hood) for (let k = 0; k <= 40; k++) neckTop = Math.min(neckTop, topAt(cut.cx + (k / 40) * torsoHalf * 0.6));
  return {
    parts,
    hanger: {
      centerY: -(cut.hood ? shoulderY - 0.02 : neckTop + 0.025),
      shoulderY: -(shoulderY + 0.06),
      halfWidth: torsoW * 0.7,
    },
  };
}
