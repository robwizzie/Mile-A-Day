// The 3D garments. Loaded on demand (dynamic import) so three.js never
// blocks first paint.
//
// Each piece is tailored from its flat-lay artwork (see tailor.ts): an oval
// torso that drapes from the shoulder seam, sleeve tubes, a hood on the
// hoodie, with the front print wrapped round the chest, the back print round
// the back and sleeve prints round the outside of the arm. A swivel hanger
// holds it: the chrome hook stays wrapped around the rail while the hanger
// body and the garment turn beneath it, the way a swivel-hook hanger does.
//
// One CSS pixel = one world unit at z = 0, so layouts are written in px.

import * as THREE from "three";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import type { Product } from "@/lib/catalog";
import { CUTS, tailor, type Tailored } from "./tailor";

// ── Assets ─────────────────────────────────────────────────────────────────

type Piece = Tailored & {
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
  // Hard-cut the edge first: a photo cutout's soft edge carries a pale halo
  // from its white background, which would otherwise be bled outward.
  const cut = document.createElement("canvas");
  cut.width = w;
  cut.height = h;
  const cctx = cut.getContext("2d", { willReadFrequently: true })!;
  cctx.drawImage(img, 0, 0);
  const data = cctx.getImageData(0, 0, w, h);
  for (let i = 3; i < data.data.length; i += 4) data.data[i] = data.data[i] > 235 ? 255 : 0;
  cctx.putImageData(data, 0, 0);

  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  const ctx = c.getContext("2d")!;
  for (const r of [24, 14, 8, 5, 3, 2, 1]) {
    for (let a = 0; a < 8; a++) {
      const t = (a / 8) * Math.PI * 2;
      ctx.drawImage(cut, Math.round(Math.cos(t) * r), Math.round(Math.sin(t) * r));
    }
  }
  ctx.drawImage(cut, 0, 0);
  ctx.globalCompositeOperation = "destination-over";
  ctx.fillStyle = averageColor(img);
  ctx.fillRect(0, 0, w, h);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  t.needsUpdate = true;
  return t;
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
  const cut = p.art.kind === "photo" ? CUTS.hoodie : CUTS[p.art.cut];
  return {
    ...tailor(front, cut),
    frontMap: texture(front),
    backMap: texture(back),
    aspect,
    scale: p.art.kind === "photo" ? p.art.scale ?? 1 : 1,
  };
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

/** Hanger body in garment units (height 1, y up from the box top): wooden
 *  shoulders along the garment's own shoulder line, and a chrome neck up to
 *  the swivel at the top of the box. */
function hangerBody(h: Tailored["hanger"]) {
  const g = new THREE.Group();
  const w = h.halfWidth;
  const curve = new THREE.CatmullRomCurve3([
    new THREE.Vector3(-w, h.shoulderY, 0),
    new THREE.Vector3(-w * 0.5, (h.shoulderY + h.centerY) / 2 + 0.008, 0),
    new THREE.Vector3(0, h.centerY, 0),
    new THREE.Vector3(w * 0.5, (h.shoulderY + h.centerY) / 2 + 0.008, 0),
    new THREE.Vector3(w, h.shoulderY, 0),
  ]);
  const bar = new THREE.Mesh(new THREE.TubeGeometry(curve, 48, 0.012, 10, false), wood());
  bar.scale.z = 0.75;
  bar.castShadow = true;
  g.add(bar);
  const neckLen = -h.centerY;
  const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.0075, 0.0075, neckLen, 12), chrome());
  neck.position.y = h.centerY / 2;
  g.add(neck);
  return g;
}

/** Fabric: double-sided, so the neckline, hem and cuffs show the inside —
 *  shaded darker, the way the inside of a garment is. */
function fabric(map: THREE.Texture) {
  const m = new THREE.MeshPhysicalMaterial({
    map,
    roughness: 0.92,
    metalness: 0,
    sheen: 0.25,
    sheenRoughness: 0.85,
    sheenColor: new THREE.Color(0xffffff),
    side: THREE.DoubleSide,
  });
  m.onBeforeCompile = (shader) => {
    shader.fragmentShader = shader.fragmentShader.replace(
      "#include <map_fragment>",
      "#include <map_fragment>\n\tif (!gl_FrontFacing) diffuseColor.rgb *= 0.42;",
    );
  };
  return m;
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

    const front = fabric(piece.frontMap);
    const back = fabric(piece.backMap);
    for (const part of piece.parts) {
      const mesh = new THREE.Mesh(part.geometry, part.side === "front" ? front : back);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      this.garment.add(mesh);
    }
    this.garment.add(hangerBody(piece.hanger));
    this.garment.scale.setScalar(h);
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

    // Dev only: lets a test pose pieces at exact angles (window.__madStages).
    if (process.env.NODE_ENV !== "production" && typeof window !== "undefined") {
      const w = window as unknown as { __madStages?: Stage[] };
      (w.__madStages ??= []).push(this);
    }
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
