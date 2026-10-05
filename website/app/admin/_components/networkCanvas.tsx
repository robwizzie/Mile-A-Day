"use client";

/**
 * The plumbing the Network tab's three canvases share: the payload types,
 * group colours, a sized + DPR-aware canvas, a redraw scheduler, and
 * pan/zoom/pinch with an optional "grab" for dragging things on the canvas.
 *
 * Canvas, not SVG: the friend web is thousands of nodes and edges redrawn on
 * every simulation tick, which an SVG tree re-rendered through React cannot
 * keep at frame rate. Everything here draws in WORLD units under a camera
 * (screen = world × k + offset) and puts text back in screen units, so a
 * label stays readable at any zoom.
 */

import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type MutableRefObject,
  type RefObject,
} from "react";
import { PALETTE } from "./theme";

// ─── Payloads (backend adminNetworkService.ts) ──────────────────────

export type NetworkNode = {
  id: string;
  username: string | null;
  name: string | null;
  joined: string;
  last_active: string | null;
  referred_by: number | null;
  friends: number;
  group: number;
  island: number;
};

export type NetworkGroup = {
  id: number;
  size: number;
  internal_edges: number;
  external_edges: number;
  hub: number;
  active_7d: number;
};

export type FriendNetwork = {
  summary: {
    total_users: number;
    connected_users: number;
    isolated_users: number;
    friendships: number;
    groups: number;
    islands: number;
    largest_island: number;
    median_friends: number;
    max_friends: number;
    pending_requests: number;
  };
  nodes: NetworkNode[];
  edges: [number, number, string | null][];
  groups: NetworkGroup[];
};

export type UserLocations = {
  cell_degrees: number;
  routes_per_person: number;
  summary: {
    total_users: number;
    located_users: number;
    active_located_users: number;
    unlocated_users: number;
  };
  cells: { lat: number; lng: number; users: number; active: number }[];
  unlocated_by_offset: { offset_minutes: number | null; users: number }[];
};

// ─── Colour + naming ────────────────────────────────────────────────

/**
 * Six clearly different hues for the six biggest groups, then grey. Groups
 * sit next to each other on the canvas, so two oranges or two blues would
 * read as one group — the palette's look-alike pairs are skipped rather than
 * cycled, and a seventh colour isn't invented.
 */
export const GROUP_COLORS = PALETTE.slice(0, 6);
export const OTHER_COLOR = PALETTE[PALETTE.length - 1];
export const groupColor = (g: number) =>
  g < GROUP_COLORS.length ? GROUP_COLORS[g] : OTHER_COLOR;

export const handle = (n: Pick<NetworkNode, "username" | "name">) =>
  n.username ? `@${n.username}` : (n.name ?? "Unnamed");

/** "Mar 3, 2026" for a YYYY-MM-DD, read as a calendar day (no tz shift). */
export function dayLabel(d: string | null | undefined): string {
  if (!d) return "—";
  const [y, m, day] = d.split("-").map(Number);
  return new Date(y, m - 1, day).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

/** Days from a YYYY-MM-DD to today, or null. */
export function daysSince(d: string | null | undefined): number | null {
  if (!d) return null;
  const [y, m, day] = d.split("-").map(Number);
  const then = new Date(y, m - 1, day).getTime();
  const now = new Date(new Date().toDateString()).getTime();
  return Math.round((now - then) / 86_400_000);
}

/** Adjacency lists, built once per payload. */
export function useAdjacency(net: FriendNetwork | null) {
  return useMemo(() => {
    if (!net) return [] as number[][];
    const adj: number[][] = net.nodes.map(() => []);
    for (const [a, b] of net.edges) {
      adj[a].push(b);
      adj[b].push(a);
    }
    return adj;
  }, [net]);
}

// ─── Canvas surface ─────────────────────────────────────────────────

export type Camera = { x: number; y: number; k: number };
export type Bounds = { x0: number; y0: number; x1: number; y1: number };

/** A canvas that tracks its box and device pixel ratio. */
export function useCanvasSurface() {
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [size, setSize] = useState({ w: 0, h: 0, dpr: 1 });

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const measure = () => {
      const r = el.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      setSize((s) =>
        s.w === Math.round(r.width) &&
        s.h === Math.round(r.height) &&
        s.dpr === dpr
          ? s
          : { w: Math.round(r.width), h: Math.round(r.height), dpr },
      );
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  useLayoutEffect(() => {
    const c = canvasRef.current;
    if (!c) return;
    c.width = Math.max(1, size.w * size.dpr);
    c.height = Math.max(1, size.h * size.dpr);
  }, [size]);

  return { wrapRef, canvasRef, size };
}

/** Coalesce redraw requests onto one animation frame. */
export function useRedraw(draw: () => void) {
  const drawRef = useRef(draw);
  useLayoutEffect(() => {
    drawRef.current = draw;
  });
  const frame = useRef(0);
  const request = useCallback(() => {
    if (frame.current) return;
    frame.current = requestAnimationFrame(() => {
      frame.current = 0;
      drawRef.current();
    });
  }, []);
  useEffect(() => () => cancelAnimationFrame(frame.current), []);
  return request;
}

/** The camera that frames `b` inside a w×h box with `pad` px to spare. */
export function cameraToFit(
  b: Bounds,
  w: number,
  h: number,
  pad: number,
  minK: number,
  maxK: number,
): Camera {
  const bw = Math.max(b.x1 - b.x0, 1);
  const bh = Math.max(b.y1 - b.y0, 1);
  const k = Math.min(
    maxK,
    Math.max(minK, Math.min((w - 2 * pad) / bw, (h - 2 * pad) / bh)),
  );
  return {
    k,
    x: w / 2 - ((b.x0 + b.x1) / 2) * k,
    y: h / 2 - ((b.y0 + b.y1) / 2) * k,
  };
}

// ─── Pan / zoom / pinch ─────────────────────────────────────────────

export type PointerInfo = {
  /** Screen position inside the canvas, CSS px. */
  sx: number;
  sy: number;
  /** The same point in world units. */
  wx: number;
  wy: number;
};

type PanZoomOpts = {
  canvasRef: RefObject<HTMLCanvasElement | null>;
  cameraRef: MutableRefObject<Camera>;
  /** The camera moved (redraw). `byUser` is false for animations. */
  onCamera: (byUser: boolean) => void;
  minK: number;
  maxK: number;
  /** Claim a press (e.g. on a node) — return true to drag it instead of panning. */
  grab?: (p: PointerInfo) => boolean;
  drag?: (p: PointerInfo) => void;
  release?: (p: PointerInfo) => void;
  hover?: (p: PointerInfo | null) => void;
  /** A press that didn't move. */
  click?: (p: PointerInfo) => void;
  doubleClick?: (p: PointerInfo) => void;
};

/**
 * Wheel / trackpad-pinch to zoom about the cursor, drag to pan, two fingers
 * to pinch on touch. Bound once with native listeners: React's wheel handler
 * is passive, and a passive listener can't stop the page scrolling under a
 * zoom.
 */
export function usePanZoom(opts: PanZoomOpts) {
  const optsRef = useRef(opts);
  useLayoutEffect(() => {
    optsRef.current = opts;
  });
  const anim = useRef(0);

  const stopAnim = () => {
    cancelAnimationFrame(anim.current);
    anim.current = 0;
  };

  useEffect(() => {
    const el = optsRef.current.canvasRef.current;
    if (!el) return;
    const o = () => optsRef.current;
    const cam = () => o().cameraRef.current;
    const pointers = new Map<number, { x: number; y: number }>();
    let mode: "none" | "pan" | "grab" | "pinch" = "none";
    let down = { x: 0, y: 0, t: 0 };
    let last = { x: 0, y: 0 };
    let moved = false;
    let pinch = { d: 1, k: 1, wx: 0, wy: 0 };

    const local = (e: { clientX: number; clientY: number }) => {
      const r = el.getBoundingClientRect();
      return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    const info = (x: number, y: number): PointerInfo => {
      const c = cam();
      return { sx: x, sy: y, wx: (x - c.x) / c.k, wy: (y - c.y) / c.k };
    };
    const clampK = (k: number) => Math.min(o().maxK, Math.max(o().minK, k));
    const zoomAt = (x: number, y: number, k: number) => {
      const c = cam();
      const nk = clampK(k);
      const wx = (x - c.x) / c.k;
      const wy = (y - c.y) / c.k;
      c.k = nk;
      c.x = x - wx * nk;
      c.y = y - wy * nk;
      stopAnim();
      o().onCamera(true);
    };
    const two = () => {
      const [a, b] = [...pointers.values()];
      return {
        d: Math.max(Math.hypot(a.x - b.x, a.y - b.y), 1),
        mx: (a.x + b.x) / 2,
        my: (a.y + b.y) / 2,
      };
    };

    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const p = local(e);
      let dy = e.deltaY;
      if (e.deltaMode === 1) dy *= 16;
      else if (e.deltaMode === 2) dy *= 400;
      // Trackpad pinch arrives as ctrl+wheel with small deltas: scale it up.
      zoomAt(p.x, p.y, cam().k * Math.exp(-dy * (e.ctrlKey ? 0.01 : 0.002)));
    };

    const onDown = (e: PointerEvent) => {
      if (e.button !== 0 && e.pointerType === "mouse") return;
      el.setPointerCapture(e.pointerId);
      const p = local(e);
      pointers.set(e.pointerId, p);
      if (pointers.size === 1) {
        down = { x: p.x, y: p.y, t: performance.now() };
        last = p;
        moved = false;
        mode = o().grab?.(info(p.x, p.y)) ? "grab" : "pan";
        if (mode === "pan") el.style.cursor = "grabbing";
        o().hover?.(null);
      } else if (pointers.size === 2) {
        if (mode === "grab") o().release?.(info(last.x, last.y));
        mode = "pinch";
        const t = two();
        const c = cam();
        pinch = { d: t.d, k: c.k, wx: (t.mx - c.x) / c.k, wy: (t.my - c.y) / c.k };
        stopAnim();
      }
    };

    const onMove = (e: PointerEvent) => {
      const p = local(e);
      if (!pointers.has(e.pointerId)) {
        o().hover?.(info(p.x, p.y));
        return;
      }
      pointers.set(e.pointerId, p);
      if (!moved && Math.hypot(p.x - down.x, p.y - down.y) > 4) moved = true;
      if (mode === "pan") {
        if (moved) {
          const c = cam();
          c.x += p.x - last.x;
          c.y += p.y - last.y;
          stopAnim();
          o().onCamera(true);
        }
        last = p;
      } else if (mode === "grab") {
        if (moved) o().drag?.(info(p.x, p.y));
        last = p;
      } else if (mode === "pinch" && pointers.size >= 2) {
        const t = two();
        const c = cam();
        const k = clampK((pinch.k * t.d) / pinch.d);
        c.k = k;
        c.x = t.mx - pinch.wx * k;
        c.y = t.my - pinch.wy * k;
        o().onCamera(true);
      }
    };

    const end = (e: PointerEvent, cancelled: boolean) => {
      if (!pointers.delete(e.pointerId)) return;
      const p = local(e);
      if (mode === "pinch") {
        // Lift one finger mid-pinch: carry on as a pan with the other.
        if (pointers.size === 1) {
          mode = "pan";
          last = [...pointers.values()][0];
          moved = true;
        } else if (pointers.size === 0) mode = "none";
        return;
      }
      if (mode === "grab") o().release?.(info(p.x, p.y));
      if (!cancelled && !moved && performance.now() - down.t < 600) {
        o().click?.(info(p.x, p.y));
      }
      mode = "none";
      el.style.cursor = "";
    };
    const onUp = (e: PointerEvent) => end(e, false);
    const onCancel = (e: PointerEvent) => end(e, true);
    const onLeave = () => {
      if (!pointers.size) o().hover?.(null);
    };
    const onDbl = (e: MouseEvent) => {
      const p = local(e);
      o().doubleClick?.(info(p.x, p.y));
    };

    el.addEventListener("wheel", onWheel, { passive: false });
    el.addEventListener("pointerdown", onDown);
    el.addEventListener("pointermove", onMove);
    el.addEventListener("pointerup", onUp);
    el.addEventListener("pointercancel", onCancel);
    el.addEventListener("pointerleave", onLeave);
    el.addEventListener("dblclick", onDbl);
    return () => {
      el.removeEventListener("wheel", onWheel);
      el.removeEventListener("pointerdown", onDown);
      el.removeEventListener("pointermove", onMove);
      el.removeEventListener("pointerup", onUp);
      el.removeEventListener("pointercancel", onCancel);
      el.removeEventListener("pointerleave", onLeave);
      el.removeEventListener("dblclick", onDbl);
      stopAnim();
    };
  }, []);

  /** Glide to a camera: centre and log-zoom interpolated, so it doesn't swoop. */
  const animateTo = useCallback((to: Camera, ms = 520) => {
    const el = optsRef.current.canvasRef.current;
    if (!el) return;
    stopAnim();
    const c = optsRef.current.cameraRef.current;
    const w = el.clientWidth;
    const h = el.clientHeight;
    const from = { cx: (w / 2 - c.x) / c.k, cy: (h / 2 - c.y) / c.k, lk: Math.log(c.k) };
    const dest = { cx: (w / 2 - to.x) / to.k, cy: (h / 2 - to.y) / to.k, lk: Math.log(to.k) };
    const start = performance.now();
    const step = () => {
      const t = Math.min(1, (performance.now() - start) / ms);
      const e = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
      const k = Math.exp(from.lk + (dest.lk - from.lk) * e);
      const cx = from.cx + (dest.cx - from.cx) * e;
      const cy = from.cy + (dest.cy - from.cy) * e;
      const cur = optsRef.current.cameraRef.current;
      cur.k = k;
      cur.x = w / 2 - cx * k;
      cur.y = h / 2 - cy * k;
      optsRef.current.onCamera(false);
      anim.current = t < 1 ? requestAnimationFrame(step) : 0;
    };
    anim.current = requestAnimationFrame(step);
  }, []);

  /** Zoom by a factor about the canvas centre (the +/− buttons). */
  const zoomBy = useCallback(
    (f: number) => {
      const el = optsRef.current.canvasRef.current;
      if (!el) return;
      const c = optsRef.current.cameraRef.current;
      const { minK, maxK } = optsRef.current;
      const k = Math.min(maxK, Math.max(minK, c.k * f));
      const w = el.clientWidth;
      const h = el.clientHeight;
      const wx = (w / 2 - c.x) / c.k;
      const wy = (h / 2 - c.y) / c.k;
      animateTo({ k, x: w / 2 - wx * k, y: h / 2 - wy * k }, 260);
    },
    [animateTo],
  );

  return { animateTo, zoomBy };
}

// ─── Drawing helpers ────────────────────────────────────────────────

/** Greedy label placement: a label is drawn only where nothing already is. */
export function labelPlacer() {
  const rects: [number, number, number, number][] = [];
  return (x0: number, y0: number, x1: number, y1: number) => {
    for (const r of rects) {
      if (x0 < r[2] && x1 > r[0] && y0 < r[3] && y1 > r[1]) return false;
    }
    rects.push([x0, y0, x1, y1]);
    return true;
  };
}

export const LABEL_FONT = (size: number, weight = 600) =>
  `${weight} ${size}px ui-rounded, "SF Pro Rounded", system-ui, -apple-system, sans-serif`;

/** Text with a dark halo so it reads over lines and dots. */
export function haloText(
  ctx: CanvasRenderingContext2D,
  text: string,
  x: number,
  y: number,
  color: string,
) {
  ctx.lineJoin = "round";
  ctx.lineWidth = 3.5;
  ctx.strokeStyle = "rgba(10,10,10,0.92)";
  ctx.strokeText(text, x, y);
  ctx.fillStyle = color;
  ctx.fillText(text, x, y);
}

/** "#d94059" + alpha → "rgba(217,64,89,a)". */
export function withAlpha(hex: string, a: number): string {
  const h = hex.replace("#", "");
  const n = parseInt(
    h.length === 3
      ? h
          .split("")
          .map((c) => c + c)
          .join("")
      : h,
    16,
  );
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}

// ─── Small shared UI ────────────────────────────────────────────────

/** Round icon-ish button for the canvas toolbars. */
export function CanvasButton({
  onClick,
  label,
  children,
  active,
}: {
  onClick: () => void;
  label: string;
  children: React.ReactNode;
  active?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      title={label}
      aria-label={label}
      aria-pressed={active}
      className={`flex h-8 min-w-8 items-center justify-center rounded-full border px-2.5 text-xs font-semibold backdrop-blur transition ${
        active
          ? "border-[#d94059]/60 bg-[#d94059]/25 text-white"
          : "border-white/[0.12] bg-[#101010]/80 text-white/70 hover:border-white/25 hover:text-white"
      }`}
    >
      {children}
    </button>
  );
}

/**
 * Find a person among the graph's nodes. Client-side on purpose: the network
 * payload already holds everyone who has a friend, and someone with none has
 * no web or tree to show.
 */
export function PersonSearch({
  nodes,
  onPick,
  placeholder = "Find a person…",
}: {
  nodes: NetworkNode[];
  onPick: (index: number) => void;
  placeholder?: string;
}) {
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const [cursor, setCursor] = useState(0);
  const matches = useMemo(() => {
    const s = q.trim().toLowerCase().replace(/^@/, "");
    if (!s) return [] as number[];
    const out: number[] = [];
    nodes.forEach((n, i) => {
      if (
        n.username?.toLowerCase().includes(s) ||
        n.name?.toLowerCase().includes(s)
      )
        out.push(i);
    });
    // Exact and prefix matches first, then the most connected.
    const rank = (i: number) => {
      const u = nodes[i].username?.toLowerCase() ?? "";
      return u === s ? 0 : u.startsWith(s) ? 1 : 2;
    };
    return out
      .sort((a, b) => rank(a) - rank(b) || nodes[b].friends - nodes[a].friends)
      .slice(0, 8);
  }, [q, nodes]);

  const pick = (i: number) => {
    onPick(i);
    setQ("");
    setOpen(false);
  };

  return (
    <div className="relative">
      <input
        value={q}
        onChange={(e) => {
          setQ(e.target.value);
          setOpen(true);
          setCursor(0);
        }}
        onFocus={() => setOpen(true)}
        onBlur={() => setTimeout(() => setOpen(false), 120)}
        onKeyDown={(e) => {
          if (e.key === "ArrowDown") {
            e.preventDefault();
            setCursor((c) => Math.min(c + 1, matches.length - 1));
          } else if (e.key === "ArrowUp") {
            e.preventDefault();
            setCursor((c) => Math.max(c - 1, 0));
          } else if (e.key === "Enter" && matches[cursor] !== undefined) {
            pick(matches[cursor]);
          } else if (e.key === "Escape") {
            setOpen(false);
          }
        }}
        placeholder={placeholder}
        className="w-full rounded-full border border-white/[0.12] bg-white/[0.04] px-3.5 py-1.5 text-sm text-white placeholder:text-white/35 focus:border-white/30 focus:outline-none"
      />
      {open && q.trim() && (
        <ul className="absolute top-full right-0 left-0 z-20 mt-1 max-h-72 overflow-y-auto rounded-xl border border-white/[0.1] bg-[#141414] py-1 shadow-xl">
          {matches.length === 0 && (
            <li className="px-3 py-2 text-sm text-white/40">
              Nobody with a friend matches.
            </li>
          )}
          {matches.map((i, idx) => {
            const n = nodes[i];
            return (
              <li key={n.id}>
                <button
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => pick(i)}
                  className={`flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm ${
                    idx === cursor ? "bg-white/[0.08]" : "hover:bg-white/[0.05]"
                  }`}
                >
                  <span
                    className="h-2.5 w-2.5 shrink-0 rounded-full"
                    style={{ background: groupColor(n.group) }}
                  />
                  <span className="min-w-0 flex-1 truncate text-white/90">
                    {handle(n)}
                    {n.username && n.name && (
                      <span className="text-white/40"> · {n.name}</span>
                    )}
                  </span>
                  <span className="shrink-0 text-xs tabular-nums text-white/40">
                    {n.friends} friends
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

/** A floating tooltip inside a canvas box, flipped away from the edges. */
export function CanvasTooltip({
  x,
  y,
  boxW,
  boxH,
  children,
}: {
  x: number;
  y: number;
  boxW: number;
  boxH: number;
  children: React.ReactNode;
}) {
  const W = 240;
  const left = x + 14 + W > boxW ? Math.max(4, x - 14 - W) : x + 14;
  const top = Math.min(Math.max(4, y + 12), Math.max(4, boxH - 120));
  return (
    <div
      className="pointer-events-none absolute z-10 rounded-xl border border-white/[0.1] bg-[#141414]/95 px-3 py-2 text-xs leading-relaxed text-white/70 shadow-xl backdrop-blur"
      style={{ left, top, width: W }}
    >
      {children}
    </div>
  );
}
