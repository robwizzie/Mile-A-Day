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
  /** How far the sleeves droop from the flat lay (radians). */
  droop: number;
};

export function drape(front: HTMLImageElement, cut: Cut, fabric: Fabric, alphaCut: number): Tailored {
  const aspect = front.naturalWidth / front.naturalHeight;

  // ── Outline ────────────────────────────────────────────────────────────
  const MW = 420;
  const MH = Math.round(MW / aspect);
  const c = document.createElement("canvas");
  c.width = MW;
  c.height = MH;
  const ctx = c.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(front, 0, 0, MW, MH);
  const raw = ctx.getImageData(0, 0, MW, MH).data;
  const A = new Float32Array(MW * MH);
  for (let i = 0; i < A.length; i++) A[i] = raw[i * 4 + 3] / 255;
  // Soften the outline's pixel steps first: on a diagonal edge they would
  // become ridges along the fabric once the surface has depth.
  boxBlur(A, MW, MH, 2, 3);
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

  // The chamfer distance is faceted; smooth it (inside only) so deep shapes
  // like the hood curve instead of stepping in terraces.
  {
    const inside = new Uint8Array(D.length);
    for (let i = 0; i < D.length; i++) inside[i] = D[i] ? 1 : 0;
    boxBlur(D, MW, MH, 6, 3);
    for (let i = 0; i < D.length; i++) if (!inside[i]) D[i] = 0;
  }

  // ── Grid, snapped to the outline ───────────────────────────────────────
  const C = 190;
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

  // Snapping each edge node on its own leaves a fine zig-zag on diagonal
  // edges; relax the edge along itself so it runs smooth.
  for (let pass = 0; pass < 4; pass++) {
    const nx = mx.slice();
    const ny = my.slice();
    for (let j = 0; j <= R; j++)
      for (let i = 0; i <= C; i++) {
        const k = idx(i, j);
        if (state[k] !== 1) continue;
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
            if (state[kk] !== 1) continue;
            sx += mx[kk];
            sy += my[kk];
            n++;
          }
        if (n >= 2) {
          nx[k] = mx[k] * 0.5 + (sx / n) * 0.5;
          ny[k] = my[k] * 0.5 + (sy / n) * 0.5;
        }
      }
    mx.set(nx);
    my.set(ny);
  }

  // ── Shape ─────────────────────────────────────────────────────────────
  const torsoW = torsoHalf * aspect; // world half-width of the body
  const EDGE = 0.02; // the seam: soft, not puffy
  const front3 = new Float32Array(N * 3);
  const back3 = new Float32Array(N * 3);
  const uvF = new Float32Array(N * 2);
  const uvB = new Float32Array(N * 2);
  const motion = new Float32Array(N * 2);
  const edge = new Float32Array(N);
  /** The garment's surface at a point of the mask (px): both layers. */
  const shape = (px: number, py: number, onEdge: boolean) => {
      const xn = px / (MW - 1);
      const yn = py / (MH - 1);
      const X = (xn - cut.cx) * aspect;
      const Y = -yn;
      const d = onEdge ? 0 : sample(D, px, py) / (MH - 1);
      const out = Math.max(0, Math.abs(X) - torsoW); // how far into a sleeve
      const inBody = 1 - smooth(0, 0.06, out);
      const sideSign = Math.sign(X) || 1;

      // Thickness: thin cloth, fuller over the hanger and through the chest.
      // The edge rolls round with a radius equal to the local thickness, the
      // way folded fabric does (a fixed narrow edge on thick fleece is a cliff
      // the mesh can only sample in steps).
      const hangerBulge = fabric.shoulders * Math.exp(-(((yn - shoulderY - 0.06) / 0.11) ** 2)) * inBody;
      const chest = 0.018 * smooth(0.02, 0.22, d) * inBody;
      const thick = fabric.body + hangerBulge + 0.018 * inBody;
      const e = Math.min(d / Math.max(EDGE, thick * 1.15), 1);
      // e(2−e): round over the edge but never vertical, so the mesh samples it
      // smoothly (a quarter-circle is vertical at the seam and steps).
      const seam = e * (2 - e);
      let half = (fabric.body + hangerBulge + chest) * seam;

      // Folds: none at the shoulders, deepening and loosening toward the hem,
      // with a softer set running down the sleeves.
      const fall = smooth(shoulderY + 0.04, hem, yn);
      const sleeveFall = smooth(0, 0.3, out);
      const bodyAmp = fabric.folds * fall * inBody;
      let F =
        bodyAmp *
        (0.5 * Math.sin((X / 0.34) * Math.PI * 2 + 1.7 + 2.2 * yn) +
          0.32 * Math.sin((X / 0.17) * Math.PI * 2 + 0.4 - 3.1 * yn) +
          0.18 * Math.sin((X / 0.085) * Math.PI * 2 + 2.6 + 5 * yn));
      // Sleeves: a couple of long, uneven folds — fine regular ones read as ribs.
      F += fabric.folds * 0.6 * sleeveFall * (1 - inBody) *
        (0.65 * Math.sin(out * 9.5 + yn * 4.0 + 0.8) + 0.35 * Math.sin(out * 21 - yn * 7.0 + 2.3));
      // Two soft folds falling from the hanger's ends.
      F += 0.5 * fabric.folds * inBody * fall * Math.exp(-(((Math.abs(X) - torsoW * 0.55) / 0.06) ** 2));
      // A loose hem.
      F += 0.4 * fabric.folds * smooth(hem - 0.14, hem, yn) * inBody * Math.sin((X / 0.1) * Math.PI * 2 + 2.1);

      // The hanger is curved; the sleeves fall back from the shoulders.
      const curve = -0.11 * X * X;
      const sleeveBack = -0.32 * out * smooth(0, 0.08, out);
      let z0 = F + curve + sleeveBack;
      let frontExtra = 0;

      // The hood: a rounded shell rising behind the face opening.
      let hoodW = 0;
      if (cut.hood) {
        hoodW = (1 - smooth(shoulderY - 0.06, shoulderY + 0.05, yn)) * inBody;
        const t = Math.min(d / 0.11, 1);
        const dome = t * (2 - t);
        half += hoodW * 0.2 * dome;
        frontExtra = -hoodW * 0.15 * dome; // the opening's rim stays forward
      }

      // Sleeves droop from the shoulder seam, the way they do on a hanger.
      let PX = X;
      let PY = Y;
      if (out > 0 && fabric.droop) {
        const th = fabric.droop * smooth(0, 0.1, out) * sideSign;
        const ox = sideSign * torsoW;
        const oy = -(shoulderY + 0.05);
        const dx = X - ox;
        const dy = Y - oy;
        PX = ox + dx * Math.cos(th) + dy * Math.sin(th);
        PY = oy - dx * Math.sin(th) + dy * Math.cos(th);
      }
      // A hem that isn't ruler-straight.
      PY += 0.006 * Math.sin(X * 38 + 1.3) * smooth(hem - 0.05, hem, yn) * inBody;

      return { xn, yn, d, PX, PY, zf: z0 + half + frontExtra, zb: z0 - half, thick, hoodW, fall, inBody, out, sideSign };
  };

  // Normals come straight from the surface (finite differences of shape()),
  // not from averaging triangles: along a snapped diagonal edge the triangles
  // are slivers, and averaged normals there flicker row to row as ribs.
  const nF = new Float32Array(N * 3);
  const nB = new Float32Array(N * 3);
  const H = 0.8;
  const normalAt = (px: number, py: number, out: Float32Array, k: number, front: boolean) => {
    const a = shape(px - H, py, false);
    const b = shape(px + H, py, false);
    const c = shape(px, py - H, false);
    const e2 = shape(px, py + H, false);
    const za = front ? a.zf : a.zb;
    const zb2 = front ? b.zf : b.zb;
    const zc = front ? c.zf : c.zb;
    const zd = front ? e2.zf : e2.zb;
    const ux = b.PX - a.PX;
    const uy = b.PY - a.PY;
    const uz = zb2 - za;
    const vx = e2.PX - c.PX;
    const vy = e2.PY - c.PY;
    const vz = zd - zc;
    let nx = uy * vz - uz * vy;
    let ny = uz * vx - ux * vz;
    let nz = ux * vy - uy * vx;
    if (front) {
      nx = -nx;
      ny = -ny;
      nz = -nz;
    }
    const len = Math.hypot(nx, ny, nz) || 1;
    out.set([nx / len, ny / len, nz / len], k * 3);
  };

  for (let k = 0; k < N; k++) {
    if (!state[k]) continue;
    const { xn, yn, d, PX, PY, zf, zb, thick, hoodW, fall, inBody, out, sideSign } = shape(mx[k], my[k], state[k] === 1);
    normalAt(mx[k], my[k], nF, k, true);
    normalAt(mx[k], my[k], nB, k, false);
    front3.set([PX, PY, zf], k * 3);
    back3.set([PX, PY, zb], k * 3);
    uvF.set([xn, 1 - yn], k * 2);
    uvB.set([1 - xn, 1 - yn], k * 2);
    // Where the surface turns edge-on (seams, the hood's sides) it shows the
    // fabric's own colour, not the print's last pixels stretched across it.
    const wall = cut.hood ? hoodW * (1 - smooth(0, 0.11, d)) : 0;
    edge[k] = Math.max(1 - smooth(0, Math.max(EDGE, thick) * 1.4, d), wall);
    // How freely this point moves when the piece swings: not at all on the
    // hanger, most at the hem and the sleeve ends.
    motion.set([Math.max(fall * inBody * (1 - hoodW), smooth(0, 0.32, out)), smooth(0, 0.12, out) * sideSign], k * 2);
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

  const geo = (pos: Float32Array, uv: Float32Array, normals: Float32Array, index: number[]) => {
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    g.setAttribute("normal", new THREE.BufferAttribute(normals, 3));
    g.setAttribute("uv", new THREE.BufferAttribute(uv, 2));
    g.setAttribute("aMotion", new THREE.BufferAttribute(motion, 2));
    g.setAttribute("aEdge", new THREE.BufferAttribute(edge, 1));
    g.setIndex(index);
    return g;
  };
  const parts: Part[] = [
    { geometry: geo(front3, uvF, nF, fIdx), side: "front" },
    { geometry: geo(back3, uvB, nB, bIdx), side: "back" },
  ];

  // Hanger: neck where the collar is lowest (or the hood's shoulders).
  let neckTop = 1;
  if (!cut.hood) for (let k = 0; k <= 40; k++) neckTop = Math.min(neckTop, topAt(cut.cx + (k / 40) * torsoHalf * 0.6));
  return {
    parts,
    // A hoodie hangs by its hood: the hook comes straight out of the top, and
    // the hanger inside is hidden.
    hanger: cut.hood
      ? { centerY: -0.03, shoulderY: -0.03, halfWidth: 0 }
      : { centerY: -(neckTop + 0.025), shoulderY: -(shoulderY + 0.06), halfWidth: torsoW * 0.7 },
  };
}

/** Separable box blur, `passes` times (≈ Gaussian), in place. */
function boxBlur(f: Float32Array, W: number, H: number, r: number, passes: number) {
  const tmp = new Float32Array(f.length);
  for (let p = 0; p < passes; p++) {
    for (let y = 0; y < H; y++) {
      let acc = 0;
      for (let k = -r; k <= r; k++) acc += f[y * W + Math.min(W - 1, Math.max(0, k))];
      for (let x = 0; x < W; x++) {
        tmp[y * W + x] = acc / (2 * r + 1);
        acc += f[y * W + Math.min(W - 1, x + r + 1)] - f[y * W + Math.max(0, x - r)];
      }
    }
    for (let x = 0; x < W; x++) {
      let acc = 0;
      for (let k = -r; k <= r; k++) acc += tmp[Math.min(H - 1, Math.max(0, k)) * W + x];
      for (let y = 0; y < H; y++) {
        f[y * W + x] = acc / (2 * r + 1);
        acc += tmp[Math.min(H - 1, y + r + 1) * W + x] - tmp[Math.max(0, y - r) * W + x];
      }
    }
  }
}
