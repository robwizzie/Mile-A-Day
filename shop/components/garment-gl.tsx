"use client";

// The garments in real 3D. One WebGL canvas per layer (the page, and the
// detail sheet above it) draws every garment into the box its placeholder
// element takes in the page, so layout, hover and scrolling stay plain DOM:
// a placeholder only says which product, and which way it should face.
//
// Each garment is a cloth model (lib/models.ts) in the piece's colour with a
// fabric sheen, its real print files projected on as decals, on a hanger
// whose hook is the top of the placeholder. Turning eases to the target with
// a little pendulum sway; nothing re-renders unless something moved.

import { createContext, useContext, useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { DecalGeometry } from "three/examples/jsm/geometries/DecalGeometry.js";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import { MeshoptDecoder } from "three/examples/jsm/libs/meshopt_decoder.module.js";
import type { Product } from "@/lib/catalog";
import { HOOK_RISE, HOOK_Z, bounds, modelUrl, type ModelId } from "@/lib/models";
import type { ModelBounds } from "@/lib/model-bounds";
import { PLACEMENTS } from "@/lib/print-placements";

type Entry = {
  el: HTMLElement;
  product: Product;
  model: ModelId;
  target: number;
  immediate: boolean;
  yaw: number;
  roll: number;
  rollVel: number;
  group: THREE.Group | null;
  onReady: () => void;
};

type Stage = {
  add: (e: Entry) => void;
  remove: (e: Entry) => void;
  poke: () => void;
};

const StageContext = createContext<Stage | null>(null);

/** Degrees per radian. */
const DEG = Math.PI / 180;
/** Field of view of each garment's camera: long-lens, product-shot perspective. */
const FOV = 18;

// ——— shared assets ————————————————————————————————————————————————

const loader = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder);
const geometries = new Map<ModelId, Promise<THREE.BufferGeometry>>();
const textures = new Map<string, Promise<THREE.Texture>>();
const garments = new Map<string, Promise<THREE.Group>>();

function geometry(id: ModelId) {
  let g = geometries.get(id);
  if (!g) {
    g = loader.loadAsync(modelUrl(id)).then((gltf) => {
      let geo: THREE.BufferGeometry | null = null;
      gltf.scene.traverse((o) => {
        const m = o as THREE.Mesh;
        if (m.isMesh && !geo) {
          geo = m.geometry.clone();
          geo.applyMatrix4(m.matrixWorld);
        }
      });
      if (!geo) throw new Error(`no mesh in ${id}`);
      return geo;
    });
    geometries.set(id, g);
  }
  return g;
}

function texture(src: string) {
  let t = textures.get(src);
  if (!t) {
    t = new THREE.TextureLoader().loadAsync(src).then((tex) => {
      tex.colorSpace = THREE.SRGBColorSpace;
      tex.anisotropy = 4;
      return tex;
    });
    textures.set(src, t);
  }
  return t;
}

/** A product's garment on its hanger, hook top at the origin. Built once per product. */
function garment(product: Product, model: ModelId) {
  let g = garments.get(product.id);
  if (!g) {
    g = build(product, model);
    garments.set(product.id, g);
  }
  return g;
}

async function build(product: Product, model: ModelId) {
  const geo = await geometry(model);
  const b = bounds(model);
  const colour = new THREE.Color(product.swatch);
  const light = colour.getHSL({ h: 0, s: 0, l: 0 }).l;
  const dark = light < 0.2;
  // Keep white and cream just under clipping, so their folds still read.
  if (light > 0.8) colour.multiplyScalar(0.86);
  const fabric = new THREE.MeshPhysicalMaterial({
    color: colour,
    roughness: 0.92,
    sheen: dark ? 0.55 : 0.35,
    sheenRoughness: 0.75,
    sheenColor: colour.clone().lerp(new THREE.Color("#ffffff"), dark ? 0.35 : 0.15),
    side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(geo, fabric);
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  const piece = new THREE.Group();
  piece.add(mesh);

  const prints = await Promise.all(
    (["front", "back"] as const).map(async (side) => {
      const p = PLACEMENTS[`${product.id}/${side}`];
      if (!p) return null;
      const decal = projectPrint(mesh, b, side, p);
      if (!decal) return null;
      const map = await texture(p.src);
      const ink = new THREE.MeshPhysicalMaterial({
        map,
        transparent: true,
        roughness: 0.75,
        depthWrite: false,
        polygonOffset: true,
        polygonOffsetFactor: -4,
      });
      const m = new THREE.Mesh(decal, ink);
      m.renderOrder = 1;
      return m;
    }),
  );
  for (const p of prints) if (p) piece.add(p);

  const hookZ = HOOK_Z[model] ?? 0;
  piece.add(hanger(b, hookZ));
  piece.position.set(0, -HOOK_RISE, -hookZ);
  const root = new THREE.Group();
  root.add(piece);
  return root;
}

/** Projects a print onto the front or back, where its placement (inches on a size M) says. */
function projectPrint(mesh: THREE.Mesh, b: ModelBounds, side: "front" | "back", p: (typeof PLACEMENTS)[string]) {
  const inch = b.chest / 20;
  const front = side === "front";
  const collar = front ? b.collarFront : b.collarBack;
  // "right" is as you look at that side: seen from behind, that's -x.
  const x = (front ? 1 : -1) * p.right * inch;
  const y = collar - (p.below + p.height / 2) * inch;
  const dir = new THREE.Vector3(0, 0, front ? -1 : 1);
  const ray = new THREE.Raycaster(new THREE.Vector3(x, y, front ? 1 : -1), dir);
  const hit = ray.intersectObject(mesh, false)[0];
  if (!hit) return null;
  const orient = new THREE.Euler(0, front ? 0 : Math.PI, 0);
  const size = new THREE.Vector3(p.width * inch, p.height * inch, Math.min(0.14, b.depth * 0.5));
  return new DecalGeometry(mesh, hit.point, orient, size);
}

const hangerMaterial = new THREE.MeshStandardMaterial({ color: "#1d1d1f", roughness: 0.38, metalness: 0.35 });

/** A wire hanger: shoulders resting inside the garment, the hook rising out of its top. */
function hanger(b: ModelBounds, z: number) {
  const g = new THREE.Group();
  const sx = b.shoulderX * 0.92;
  const sy = b.shoulderY - 0.012;
  const shoulders = new THREE.CatmullRomCurve3([
    new THREE.Vector3(-sx, sy - 0.035, 0),
    new THREE.Vector3(-sx * 0.55, sy - 0.012, 0),
    new THREE.Vector3(0, sy + 0.02, 0),
    new THREE.Vector3(sx * 0.55, sy - 0.012, 0),
    new THREE.Vector3(sx, sy - 0.035, 0),
  ]);
  g.add(new THREE.Mesh(new THREE.TubeGeometry(shoulders, 48, 0.006, 8, false), hangerMaterial));
  // Neck and hook: straight up through the collar (or hood), then over the
  // rail in an arc whose top is the hook's top (y = HOOK_RISE).
  const top = HOOK_RISE;
  const r = 0.02;
  const points = [new THREE.Vector3(0, sy + 0.02, 0), new THREE.Vector3(0, sy + 0.06, z * 0.8), new THREE.Vector3(0, (sy + top - r) / 2, z)];
  for (let i = 0; i <= 28; i++) {
    const a = Math.PI - (i / 28) * (Math.PI + 0.45);
    points.push(new THREE.Vector3(r + r * Math.cos(a), top - r + r * Math.sin(a), z));
  }
  const hook = new THREE.CatmullRomCurve3(points, false, "centripetal");
  g.add(new THREE.Mesh(new THREE.TubeGeometry(hook, 64, 0.0045, 8, false), hangerMaterial));
  return g;
}

// ——— stage ————————————————————————————————————————————————————————

/**
 * The canvas for one layer. Put it once in the page and once inside each
 * overlay; garments under it register themselves.
 */
export function GarmentStage({ zIndex, children }: { zIndex: number; children: ReactNode }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [stage, setStage] = useState<Stage | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current!;
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "high-performance" });
    } catch {
      return; // No WebGL: the placeholders keep showing the photos.
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping = THREE.NeutralToneMapping;
    renderer.toneMappingExposure = 1;
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    // Self-shadowing (a sleeve on the body, the hood on the shoulders) is
    // most of what makes cloth read as cloth.
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.setClearColor(0x000000, 0);
    // One clear per frame (below); each garment then draws into its own box.
    renderer.autoClear = false;

    const scene = new THREE.Scene();
    const pmrem = new THREE.PMREMGenerator(renderer);
    scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    scene.environmentIntensity = 0.6;
    const key = new THREE.DirectionalLight("#ffffff", 2.1);
    key.position.set(-1.3, 1.4, 2.2);
    key.target.position.set(0, -0.45, 0);
    key.castShadow = true;
    key.shadow.mapSize.set(1024, 1024);
    key.shadow.camera.left = key.shadow.camera.bottom = -0.75;
    key.shadow.camera.right = key.shadow.camera.top = 0.75;
    key.shadow.camera.near = 0.5;
    key.shadow.camera.far = 6;
    key.shadow.bias = -0.0004;
    key.shadow.normalBias = 0.012;
    key.shadow.radius = 4;
    scene.add(key, key.target);
    const rim = new THREE.DirectionalLight("#ffffff", 0.5);
    rim.position.set(1.5, 0.6, -1.5);
    scene.add(rim);
    const camera = new THREE.PerspectiveCamera(FOV, 1, 0.05, 40);

    const entries = new Set<Entry>();
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let dirty = true;
    let last = performance.now();
    let lastKey = "";
    let raf = 0;
    let hangerTick = 0;

    const size = () => {
      renderer.setSize(window.innerWidth, window.innerHeight, false);
      dirty = true;
    };
    size();
    window.addEventListener("resize", size);

    const frame = (now: number) => {
      raf = requestAnimationFrame(frame);
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      if (document.hidden) return;

      // The hanger follows the theme.
      if (hangerTick-- <= 0) {
        hangerTick = 30;
        const c = getComputedStyle(document.documentElement).getPropertyValue("--hanger").trim();
        if (c && `#${hangerMaterial.color.getHexString()}` !== c.toLowerCase()) {
          hangerMaterial.color.set(c);
          dirty = true;
        }
      }

      let moving = false;
      const boxes: { e: Entry; r: DOMRect; clip: { l: number; t: number; r: number; b: number } }[] = [];
      for (const e of entries) {
        const extra = Number((e.el.closest("[data-yaw]") as HTMLElement | null)?.dataset.yaw ?? 0);
        const target = e.target + extra;
        if (e.immediate || reduceMotion.matches) e.yaw = target;
        else {
          const before = e.yaw;
          e.yaw += (target - e.yaw) * (1 - Math.exp(-dt * 6.5));
          if (Math.abs(target - e.yaw) < 0.05) e.yaw = target;
          // The turn's swing becomes a little sway about the hook.
          e.rollVel += -(e.yaw - before) * 0.006;
        }
        e.rollVel += (-60 * e.roll - 4.5 * e.rollVel) * dt;
        e.roll += e.rollVel * dt;
        if (Math.abs(e.roll) < 1e-5 && Math.abs(e.rollVel) < 1e-5) e.roll = e.rollVel = 0;
        if (e.yaw !== target || e.roll !== 0) moving = true;
        if (!e.group) continue;
        const r = e.el.getBoundingClientRect();
        if (r.width < 1 || r.bottom < 0 || r.top > window.innerHeight || r.right < 0 || r.left > window.innerWidth) continue;
        let clip = { l: 0, t: 0, r: window.innerWidth, b: window.innerHeight };
        for (let a = e.el.parentElement?.closest<HTMLElement>("[data-gl-clip]"); a; a = a.parentElement?.closest<HTMLElement>("[data-gl-clip]")) {
          const c = a.getBoundingClientRect();
          clip = { l: Math.max(clip.l, c.left), t: Math.max(clip.t, c.top), r: Math.min(clip.r, c.right), b: Math.min(clip.b, c.bottom) };
        }
        if (clip.r <= clip.l || clip.b <= clip.t) continue;
        boxes.push({ e, r, clip });
      }

      const key = boxes.map(({ e, r, clip }) => `${e.product.id}${r.left | 0},${r.top | 0},${r.width | 0},${clip.l | 0},${clip.r | 0},${e.yaw.toFixed(2)},${e.roll.toFixed(4)}`).join("|");
      if (!dirty && !moving && key === lastKey) return;
      lastKey = key;
      dirty = false;

      renderer.setScissorTest(false);
      renderer.clear();
      renderer.setScissorTest(true);
      const H = window.innerHeight;
      for (const { e, r, clip } of boxes) {
        const b = bounds(e.model);
        // The placeholder's box is the whole hung piece, hook to hem.
        const worldH = b.height + HOOK_RISE;
        const w = r.width, h = r.height;
        camera.aspect = w / h;
        camera.fov = FOV;
        const dist = worldH / 2 / Math.tan((FOV * DEG) / 2);
        camera.position.set(0, -worldH / 2, dist);
        camera.lookAt(0, -worldH / 2, 0);
        camera.updateProjectionMatrix();

        for (const other of entries) if (other.group) other.group.visible = other === e;
        e.group!.rotation.set(0, e.yaw * DEG, e.roll);
        renderer.setViewport(r.left, H - r.bottom, w, h);
        renderer.setScissor(clip.l, H - clip.b, clip.r - clip.l, clip.b - clip.t);
        renderer.clearDepth();
        renderer.render(scene, camera);
      }
    };
    raf = requestAnimationFrame(frame);

    setStage({
      add: (e) => {
        entries.add(e);
        garment(e.product, e.model).then((proto) => {
          if (!entries.has(e)) return;
          e.group = proto.clone();
          scene.add(e.group);
          dirty = true;
          e.onReady();
        });
      },
      remove: (e) => {
        entries.delete(e);
        if (e.group) scene.remove(e.group);
        dirty = true;
      },
      poke: () => {
        dirty = true;
      },
    });

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", size);
      pmrem.dispose();
      renderer.dispose();
      setStage(null);
    };
  }, []);

  return (
    <StageContext.Provider value={stage}>
      {children}
      <canvas
        ref={canvasRef}
        aria-hidden="true"
        className="pointer-events-none fixed inset-0 h-full w-full"
        style={{ zIndex }}
      />
    </StageContext.Provider>
  );
}

/**
 * A garment's place in the page. Shows the photo until its 3D model is in,
 * then hands over to the stage, which draws it here facing `turn` degrees
 * (0 the front, ±180 the back).
 */
export function GlGarment({
  product,
  model,
  width,
  height,
  turn,
  immediate,
  photo,
  className,
  style,
}: {
  product: Product;
  model: ModelId;
  width: number;
  height: number;
  turn: number;
  immediate: boolean;
  photo: ReactNode;
  className?: string;
  style?: CSSProperties;
}) {
  const stage = useContext(StageContext);
  const el = useRef<HTMLDivElement>(null);
  const entry = useRef<Entry | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!stage || !el.current) return;
    const e: Entry = {
      el: el.current,
      product,
      model,
      target: turn,
      immediate: true,
      yaw: turn,
      roll: 0,
      rollVel: 0,
      group: null,
      onReady: () => setReady(true),
    };
    entry.current = e;
    stage.add(e);
    return () => {
      stage.remove(e);
      entry.current = null;
      setReady(false);
    };
    // Re-register only when the stage or the piece changes; turn updates below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stage, product.id, model]);

  useEffect(() => {
    const e = entry.current;
    if (!e) return;
    e.target = turn;
    e.immediate = immediate;
    stage?.poke();
  }, [turn, immediate, stage]);

  return (
    <div ref={el} className={`relative ${className ?? ""}`} style={{ width, height, ...style }}>
      <div className="absolute inset-0 transition-opacity duration-500" style={{ opacity: ready ? 0 : 1 }}>
        {photo}
      </div>
    </div>
  );
}
