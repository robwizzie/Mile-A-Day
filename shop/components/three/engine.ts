// The 3D garments. Loaded on demand (dynamic import) so three.js never
// blocks first paint.
//
// Each piece is built from its own artwork: the print's alpha outline is
// "inflated" into a soft volume — flat across the body, rounded at the edges,
// slightly draped — with the front print on the front surface and the back
// print on the back. The two surfaces meet at the outline, so a piece seen
// edge-on has real thickness and no gaps. A swivel hanger holds it: the
// chrome hook stays wrapped around the rail while the hanger body and the
// garment turn beneath it, the way a swivel-hook hanger does.
//
// One CSS pixel = one world unit at z = 0, so layouts are written in px.

import * as THREE from "three";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import type { Product } from "@/lib/catalog";

// ── Assets ─────────────────────────────────────────────────────────────────

type Piece = {
  front: THREE.BufferGeometry;
  back: THREE.BufferGeometry;
  frontMap: THREE.Texture;
  backMap: THREE.Texture;
  /** Width ÷ height of the garment box. */
  aspect: number;
  /** Garment box height relative to the rack height (the hoodie hangs larger). */
  scale: number;
};

const pieces = new Map<string, Promise<Piece>>();

export function loadPiece(p: Product): Promise<Piece> {
  let piece = pieces.get(p.id);
  if (!piece) {
    piece = buildPiece(p);
    pieces.set(p.id, piece);
  }
  return piece;
}

function urls(p: Product) {
  return p.art.kind === "photo"
    ? { front: p.art.front, back: p.art.back }
    : { front: `/garments/${p.id}-front.webp`, back: `/garments/${p.id}-back.webp` };
}

async function loadImage(src: string) {
  const img = new Image();
  img.decoding = "async";
  img.src = src;
  await img.decode();
  return img;
}

/** The print as an opaque texture. The mesh is the silhouette, so the
 *  transparent margin is filled with the fabric's own colour (bled outward
 *  from the edge) — otherwise the rounded rim shows the edge's fringe when
 *  a piece turns side-on. */
function texture(img: HTMLImageElement) {
  const w = img.naturalWidth;
  const h = img.naturalHeight;
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  const ctx = c.getContext("2d")!;
  for (const r of [24, 14, 8, 5, 3, 2, 1]) {
    for (let a = 0; a < 8; a++) {
      const t = (a / 8) * Math.PI * 2;
      ctx.drawImage(img, Math.round(Math.cos(t) * r), Math.round(Math.sin(t) * r));
    }
  }
  ctx.drawImage(img, 0, 0);
  ctx.globalCompositeOperation = "destination-over";
  ctx.fillStyle = averageColor(img);
  ctx.fillRect(0, 0, w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  t.needsUpdate = true;
  return t;
}

/** How thick each cut is (fraction of its height): fleece is fuller. */
function depthFor(p: Product) {
  if (p.art.kind === "photo") return 0.11;
  return p.art.cut === "tank" ? 0.05 : 0.065;
}

function averageColor(img: HTMLImageElement) {
  const c = document.createElement("canvas");
  c.width = 32;
  c.height = 32;
  const ctx = c.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(img, 0, 0, 32, 32);
  const d = ctx.getImageData(0, 0, 32, 32).data;
  let r = 0;
  let g = 0;
  let b = 0;
  let n = 0;
  for (let i = 0; i < d.length; i += 4) {
    if (d[i + 3] < 250) continue;
    r += d[i];
    g += d[i + 1];
    b += d[i + 2];
    n++;
  }
  return n ? `rgb(${r / n | 0},${g / n | 0},${b / n | 0})` : "#888";
}

async function buildPiece(p: Product): Promise<Piece> {
  const u = urls(p);
  const [front, back] = await Promise.all([loadImage(u.front), loadImage(u.back)]);
  const aspect = front.naturalWidth / front.naturalHeight;
  // A photo's cutout keeps a pale halo from its white studio background;
  // cut the outline just inside it.
  const { frontGeo, backGeo } = inflate(front, aspect, depthFor(p), p.art.kind === "photo" ? 0.9 : 0.5);
  return {
    front: frontGeo,
    back: backGeo,
    frontMap: texture(front),
    backMap: texture(back),
    aspect,
    scale: p.art.kind === "photo" ? p.art.scale ?? 1 : 1,
  };
}

// ── Inflating an outline into a garment ────────────────────────────────────

function inflate(img: HTMLImageElement, aspect: number, depth: number, cut: number) {
  // Alpha mask.
  const MW = 260;
  const MH = Math.round(MW / aspect);
  const c = document.createElement("canvas");
  c.width = MW;
  c.height = MH;
  const ctx = c.getContext("2d", { willReadFrequently: true })!;
  ctx.drawImage(img, 0, 0, MW, MH);
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
    return (
      field[i] * (1 - fx) * (1 - fy) + field[i + 1] * fx * (1 - fy) + field[i + MW] * (1 - fx) * fy + field[i + MW + 1] * fx * fy
    );
  };

  // Distance from the outline, inside the garment (chamfer transform, px).
  const D = new Float32Array(MW * MH);
  for (let i = 0; i < D.length; i++) D[i] = A[i] >= cut ? 1e6 : 0;
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

  // Node grid.
  const C = 120;
  const R = Math.round(C / aspect);
  const N = (C + 1) * (R + 1);
  const mx = new Float32Array(N);
  const my = new Float32Array(N);
  const state = new Uint8Array(N); // 0 out, 1 boundary, 2 inside
  const idx = (i: number, j: number) => j * (C + 1) + i;
  for (let j = 0; j <= R; j++)
    for (let i = 0; i <= C; i++) {
      const k = idx(i, j);
      mx[k] = (i / C) * (MW - 1);
      my[k] = (j / R) * (MH - 1);
      state[k] = sample(A, mx[k], my[k]) >= cut ? 2 : 0;
    }
  // Boundary nodes sit just outside; pull each onto the outline itself so the
  // silhouette is smooth instead of stair-stepped.
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
          let hi = 1; // lo outside, hi inside
          for (let s = 0; s < 7; s++) {
            const t = (lo + hi) / 2;
            const a = sample(A, mx[k] + (mx[kk] - mx[k]) * t, my[k] + (my[kk] - my[k]) * t);
            if (a >= cut) hi = t;
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

  // Surface height: flat across the body, a rounded edge, a gentle drape.
  const half = depth / 2;
  const edge = 0.055;
  const front = new Float32Array(N * 3);
  const back = new Float32Array(N * 3);
  const uvF = new Float32Array(N * 2);
  const uvB = new Float32Array(N * 2);
  for (let k = 0; k < N; k++) {
    if (!state[k]) continue;
    const x = (mx[k] / (MW - 1) - 0.5) * aspect;
    const y = -my[k] / (MH - 1);
    const d = state[k] === 2 ? sample(D, mx[k], my[k]) / (MH - 1) : 0;
    const t = Math.min(d / edge, 1);
    const body = Math.min(d / 0.22, 1);
    let z = half * Math.sqrt(t * (2 - t));
    z += 0.012 * body * body; // a little fullness through the middle
    z += 0.0035 * body * Math.sin(9 * x + 4 * y) * Math.sin(6 * y + 1.3); // fabric, not plastic
    const drape = -0.1 * x * x;
    front.set([x, y, drape + z], k * 3);
    back.set([x, y, drape - z], k * 3);
    const uu = mx[k] / (MW - 1);
    const vv = 1 - my[k] / (MH - 1);
    uvF.set([uu, vv], k * 2);
    uvB.set([1 - uu, vv], k * 2);
  }

  const fIdx: number[] = [];
  const bIdx: number[] = [];
  const tri = (a: number, b: number, c: number) => {
    if (!state[a] || !state[b] || !state[c]) return;
    if (state[a] !== 2 && state[b] !== 2 && state[c] !== 2) return;
    // Skip triangles that would web across a gap (between sleeve and body).
    const cx = (mx[a] + mx[b] + mx[c]) / 3;
    const cy = (my[a] + my[b] + my[c]) / 3;
    if (sample(A, cx, cy) < cut * 0.7) return;
    fIdx.push(a, b, c);
    bIdx.push(a, c, b);
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
  return { frontGeo: geo(front, uvF, fIdx), backGeo: geo(back, uvB, bIdx) };
}

// ── Hanger + rail ──────────────────────────────────────────────────────────

const chrome = () =>
  new THREE.MeshStandardMaterial({ color: 0xe8e8ea, metalness: 1, roughness: 0.22 });
const wood = () => new THREE.MeshStandardMaterial({ color: 0xcfae86, metalness: 0, roughness: 0.55 });

/** The hook, in px, around a rail of radius `railR` centred at the origin:
 *  a straight shank rising on the near side, curling over the top and down
 *  the far side. Returns the hook and where the shank ends (the swivel). */
function hookMesh(railR: number, wire: number, shank: number) {
  const r = railR + wire * 1.15;
  const pts: THREE.Vector3[] = [];
  for (let s = 0; s <= 12; s++) pts.push(new THREE.Vector3(0, -shank + (shank * s) / 12, r));
  for (let s = 1; s <= 30; s++) {
    const a = (s / 30) * (Math.PI * 1.28); // from the front, over the top, down the back
    pts.push(new THREE.Vector3(0, r * Math.sin(a), r * Math.cos(a)));
  }
  const curve = new THREE.CatmullRomCurve3(pts);
  const geo = new THREE.TubeGeometry(curve, 90, wire, 12, false);
  const mesh = new THREE.Mesh(geo, chrome());
  mesh.castShadow = true;
  // A rounded tip.
  const tip = new THREE.Mesh(new THREE.SphereGeometry(wire, 12, 8), mesh.material);
  tip.position.copy(pts[pts.length - 1]);
  mesh.add(tip);
  return { mesh, swivel: new THREE.Vector3(0, -shank, r) };
}

/** Hanger body in garment units (height 1): shoulders that sit inside the
 *  garment, with a short neck up to the swivel. */
function hangerBody(width: number) {
  const g = new THREE.Group();
  const curve = new THREE.CatmullRomCurve3([
    new THREE.Vector3(-width / 2, -0.14, 0),
    new THREE.Vector3(-width / 4, -0.085, 0),
    new THREE.Vector3(0, -0.05, 0),
    new THREE.Vector3(width / 4, -0.085, 0),
    new THREE.Vector3(width / 2, -0.14, 0),
  ]);
  const bar = new THREE.Mesh(new THREE.TubeGeometry(curve, 48, 0.014, 10, false), wood());
  bar.scale.z = 0.7;
  bar.castShadow = true;
  g.add(bar);
  const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.009, 0.012, 0.06, 12), chrome());
  neck.position.y = -0.02;
  g.add(neck);
  return g;
}

// ── Springs ────────────────────────────────────────────────────────────────

class Spring {
  v = 0;
  constructor(
    public x: number,
    public target: number,
    private k: number,
    private zeta: number,
  ) {}
  set(t: number, immediate = false) {
    this.target = t;
    if (immediate) {
      this.x = t;
      this.v = 0;
    }
  }
  step(dt: number) {
    const c = 2 * Math.sqrt(this.k) * this.zeta;
    const a = -this.k * (this.x - this.target) - c * this.v;
    this.v += a * dt;
    this.x += this.v * dt;
  }
  get settled() {
    return Math.abs(this.x - this.target) < 0.02 && Math.abs(this.v) < 0.02;
  }
}

// ── A hung piece ───────────────────────────────────────────────────────────

export class HungPiece {
  readonly root = new THREE.Group();
  private rock = new THREE.Group();
  private swivel = new THREE.Group();
  private garment = new THREE.Group();
  readonly x: Spring;
  readonly turn: Spring;
  private rockX = new Spring(0, 0, 38, 0.18);
  private rockZ = new Spring(0, 0, 50, 0.22);
  private drop: Spring;
  private dropDelay = 0;
  ready = false;
  /** Resolves once the garment is built and on its hanger. */
  readonly loaded: Promise<void>;
  private resolveLoaded!: () => void;

  constructor(
    readonly product: Product,
    private stage: Stage,
    private heightPx: number,
    opts: { x: number; turn: number; dropIn?: number },
  ) {
    this.x = new Spring(opts.x, opts.x, 140, 0.9);
    this.turn = new Spring(opts.turn, opts.turn, 110, 0.8);
    this.drop = new Spring(opts.dropIn != null ? 1 : 0, 0, 70, 0.75);
    this.dropDelay = opts.dropIn ?? 0;
    this.root.add(this.rock);
    this.rock.add(this.swivel);
    this.swivel.add(this.garment);
    this.root.visible = false;
    this.loaded = new Promise((r) => (this.resolveLoaded = r));
    void this.build();
  }

  private generation = 0;

  private async build() {
    // A resize can start a rebuild while the first build is still loading;
    // only the newest one may attach.
    const gen = ++this.generation;
    const piece = await loadPiece(this.product);
    if (gen !== this.generation) return;
    const h = this.heightPx * piece.scale;
    const shank = Math.max(18, this.heightPx * 0.13);
    const { mesh: hook, swivel } = hookMesh(this.stage.railR, Math.max(1.5, this.heightPx * 0.0062), shank);
    this.rock.add(hook);
    this.swivel.position.copy(swivel);

    const mat = (map: THREE.Texture) =>
      new THREE.MeshPhysicalMaterial({
        map,
        roughness: 0.9,
        metalness: 0,
        sheen: 0.25,
        sheenRoughness: 0.85,
        sheenColor: new THREE.Color(0xffffff),
      });
    const f = new THREE.Mesh(piece.front, mat(piece.frontMap));
    const b = new THREE.Mesh(piece.back, mat(piece.backMap));
    for (const m of [f, b]) {
      m.castShadow = true;
      m.receiveShadow = true;
    }
    this.garment.add(f, b);
    // The hanger sits on the shoulders, which on a hoodie are below the hood.
    const hood = this.product.art.kind === "photo";
    const body = hangerBody(piece.aspect * (hood ? 0.34 : 0.42));
    body.position.y = hood ? -0.2 : 0;
    this.garment.add(body);
    if (hood) {
      // A longer neck reaches the hook through the hood.
      const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.008, 0.008, 0.22, 10), chrome());
      neck.position.y = -0.11;
      this.garment.add(neck);
    }
    this.garment.scale.setScalar(h);
    this.garment.position.y = -0.012 * h;
    this.ready = true;
    this.root.visible = true;
    this.resolveLoaded();
    this.stage.invalidate();
  }

  setHeight(px: number) {
    if (Math.abs(px - this.heightPx) < 1) return;
    // Rebuild at the new size (resizes are rare).
    this.heightPx = px;
    this.rock.clear();
    this.rock.add(this.swivel);
    this.garment.clear();
    this.ready = false;
    void this.build();
  }

  /** A nudge, as if brushed by a hand. */
  kick(strength = 1) {
    this.rockX.v += 2.4 * strength;
    this.rockZ.v -= 0.8 * strength;
    this.stage.invalidate();
  }

  step(dt: number, now: number) {
    this.x.step(dt);
    this.turn.step(dt);
    this.rockX.step(dt);
    this.rockZ.step(dt);
    if (now >= this.dropDelay) this.drop.step(dt);
    this.root.position.x = this.x.x;
    this.root.position.y = this.stage.railY + this.drop.x * 22;
    this.swivel.rotation.y = THREE.MathUtils.degToRad(this.turn.x);
    this.rock.rotation.x = this.rockX.x * 0.06;
    this.rock.rotation.z = this.rockZ.x * 0.02;
  }

  get settled() {
    return this.x.settled && this.turn.settled && this.rockX.settled && this.rockZ.settled && this.drop.settled;
  }
}

// ── Stage ──────────────────────────────────────────────────────────────────

export class Stage {
  readonly renderer: THREE.WebGLRenderer;
  readonly scene = new THREE.Scene();
  readonly camera = new THREE.PerspectiveCamera(24, 1, 10, 20000);
  readonly pieces: HungPiece[] = [];
  railY = 0;
  readonly railR: number;
  private rail = new THREE.Group();
  private wall: THREE.Mesh<THREE.PlaneGeometry, THREE.ShadowMaterial>;
  private key: THREE.DirectionalLight;
  private rim: THREE.DirectionalLight;
  private w = 1;
  private h = 1;
  private raf = 0;
  private last = 0;
  private start = performance.now();
  private disposed = false;
  /** Called after every frame (cards copy the frame out). */
  onFrame?: () => void;

  constructor(
    canvas: HTMLCanvasElement | OffscreenCanvas,
    opts: { railR?: number; shadowSize?: number } = {},
  ) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: false });
    this.renderer.setClearColor(0x000000, 0);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.NeutralToneMapping;
    this.renderer.toneMappingExposure = 1;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.VSMShadowMap;
    this.railR = opts.railR ?? 4;

    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    this.scene.environmentIntensity = 0.62;
    pmrem.dispose();

    this.key = new THREE.DirectionalLight(0xffffff, 1.15);
    this.key.castShadow = true;
    this.key.shadow.mapSize.setScalar(opts.shadowSize ?? 2048);
    this.key.shadow.radius = 10;
    this.key.shadow.blurSamples = 20;
    this.key.shadow.bias = -0.0004;
    this.scene.add(this.key, this.key.target);

    this.rim = new THREE.DirectionalLight(0xffffff, 0);
    this.scene.add(this.rim);

    this.wall = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.ShadowMaterial({ opacity: 0.1 }));
    this.wall.receiveShadow = true;
    this.scene.add(this.wall, this.rail);
  }

  setTheme(dark: boolean) {
    this.wall.material.opacity = dark ? 0.45 : 0.1;
    this.rim.intensity = dark ? 2.2 : 0;
    this.scene.environmentIntensity = dark ? 0.55 : 0.62;
    this.invalidate();
  }

  /** Canvas size in CSS px. */
  resize(w: number, h: number) {
    this.w = w;
    this.h = h;
    this.renderer.setPixelRatio(Math.min(typeof window === "undefined" ? 1 : window.devicePixelRatio, 2));
    this.renderer.setSize(w, h, false);
    const fov = THREE.MathUtils.degToRad(this.camera.fov);
    const dist = h / 2 / Math.tan(fov / 2);
    this.camera.aspect = w / h;
    this.camera.position.set(0, 0, dist);
    this.camera.near = dist / 10;
    this.camera.far = dist * 10;
    this.camera.updateProjectionMatrix();

    const span = Math.max(w, h) * 1.4;
    const depth = Math.min(h * 0.38, 260);
    this.wall.geometry.dispose();
    this.wall.geometry = new THREE.PlaneGeometry(span * 2, span * 2);
    this.wall.position.z = -depth;
    this.key.position.set(-w * 0.12, h * 0.55, dist);
    this.key.target.position.set(0, 0, -depth);
    const cam = this.key.shadow.camera;
    cam.left = -span;
    cam.right = span;
    cam.top = span;
    cam.bottom = -span;
    cam.near = 1;
    cam.far = dist * 4;
    cam.updateProjectionMatrix();
    this.rim.position.set(w * 0.3, h * 0.8, -dist);
    this.invalidate();
  }

  /** CSS px (from the canvas's top-left) → world. */
  wx(px: number) {
    return px - this.w / 2;
  }
  wy(py: number) {
    return this.h / 2 - py;
  }

  /** A chrome rail from x0 to x1 at y (CSS px). */
  setRail(x0: number, x1: number, y: number) {
    this.railY = this.wy(y);
    this.rail.clear();
    const len = x1 - x0;
    const mat = chrome();
    const bar = new THREE.Mesh(new THREE.CylinderGeometry(this.railR, this.railR, len, 24), mat);
    bar.rotation.z = Math.PI / 2;
    const caps = [x0, x1].map((x) => {
      const cap = new THREE.Mesh(new THREE.SphereGeometry(this.railR * 1.7, 20, 14), mat);
      cap.position.x = this.wx(x);
      return cap;
    });
    bar.position.x = this.wx((x0 + x1) / 2);
    this.rail.add(bar, ...caps);
    this.rail.position.y = this.railY;
    this.invalidate();
  }

  add(product: Product, heightPx: number, opts: { x: number; turn: number; dropIn?: number }) {
    const p = new HungPiece(product, this, heightPx, { ...opts, x: this.wx(opts.x), dropIn: opts.dropIn });
    this.pieces.push(p);
    this.scene.add(p.root);
    this.invalidate();
    return p;
  }

  invalidate() {
    if (this.disposed || this.raf) return;
    this.last = performance.now();
    this.raf = requestAnimationFrame(this.tick);
  }

  private tick = (now: number) => {
    this.raf = 0;
    const dt = Math.min((now - this.last) / 1000, 1 / 30);
    this.last = now;
    // Small fixed sub-steps keep the springs stable at any frame rate.
    const steps = Math.max(1, Math.ceil(dt / (1 / 240)));
    for (let s = 0; s < steps; s++) for (const p of this.pieces) p.step(dt / steps, now - this.start);
    this.renderer.render(this.scene, this.camera);
    this.onFrame?.();
    if (this.pieces.some((p) => !p.settled || !p.ready)) this.raf = requestAnimationFrame(this.tick);
  };

  remove(piece: HungPiece) {
    this.scene.remove(piece.root);
    this.pieces.splice(this.pieces.indexOf(piece), 1);
    this.invalidate();
  }

  renderNow() {
    for (const p of this.pieces) p.step(0, performance.now() - this.start);
    this.renderer.render(this.scene, this.camera);
  }

  dispose() {
    this.disposed = true;
    cancelAnimationFrame(this.raf);
    this.renderer.dispose();
  }
}

/** True when the browser can draw WebGL at all. */
export function webglAvailable() {
  try {
    const c = document.createElement("canvas");
    return !!(c.getContext("webgl2") || c.getContext("webgl"));
  } catch {
    return false;
  }
}

// ── Collection cards: one shared renderer, frames copied into each card ───

export class CardRenderer {
  private stage: Stage;
  private hung = new Map<string, HungPiece>();
  private canvas = document.createElement("canvas");

  constructor(
    private w: number,
    private h: number,
    private garmentH: (p: Product) => number,
  ) {
    this.stage = new Stage(this.canvas, { railR: 3, shadowSize: 1024 });
    this.stage.resize(w, h);
    this.stage.setRail(w * 0.2, w * 0.8, 22);
  }

  setTheme(dark: boolean) {
    this.stage.setTheme(dark);
  }

  async draw(p: Product, turn: number, target: HTMLCanvasElement) {
    let piece = this.hung.get(p.id);
    if (!piece) {
      piece = this.stage.add(p, this.garmentH(p), { x: this.w / 2, turn });
      this.hung.set(p.id, piece);
    }
    await piece.loaded;
    for (const q of this.stage.pieces) q.root.visible = q === piece;
    piece.turn.set(turn, true);
    this.stage.renderNow();
    const ctx = target.getContext("2d");
    if (!ctx) return;
    ctx.clearRect(0, 0, target.width, target.height);
    ctx.drawImage(this.stage.renderer.domElement, 0, 0, target.width, target.height);
  }
}
