"use client";

/**
 * One person's corner of the web, laid out on a JOIN-DATE timeline.
 *
 * Three rows, top to bottom: the person, their friends, and their friends'
 * friends who are NOT their friends ("adjacent" — the people one introduction
 * away). Left-to-right is when each joined the app, so the picture answers
 * "did this person arrive first and pull their friends in, or join a crowd
 * that was already here?" A dashed line marks the day the centre person
 * joined; amber dashed arrows are referrals (who named whom at onboarding).
 *
 * Two people who joined the same week stack vertically rather than overlap.
 */

import { useEffect, useMemo, useRef, useState } from "react";
import {
  CanvasButton,
  CanvasTooltip,
  cameraToFit,
  dayLabel,
  groupColor,
  handle,
  haloText,
  LABEL_FONT,
  labelPlacer,
  PersonSearch,
  useCanvasSurface,
  usePanZoom,
  useRedraw,
  withAlpha,
  type Bounds,
  type Camera,
  type FriendNetwork,
} from "./networkCanvas";
import { MAD_WARNING } from "./theme";

/** Friends-of-friends shown at most; the best-connected are kept. */
const ADJACENT_CAP = 300;
const WORLD_W = 1200;
const PAD_X = 40;
const LANE_GAP = 95;
const RADIUS = [13, 7.5, 5] as const;
const LANE_NAMES = ["This person", "Friends", "Friends of friends"] as const;
/** Below this zoom, dots and names are too small to read. */
const MIN_READABLE_K = 0.6;

type Placed = { i: number; lane: 0 | 1 | 2; x: number; y: number; r: number };
type Edge = { a: number; b: number; kind: "root" | "peer" | "bridge" | "outer" };

const dayNum = (d: string) => {
  const [y, m, day] = d.split("-").map(Number);
  return Date.UTC(y, m - 1, day) / 86_400_000;
};

/**
 * Stack same-time people vertically. Each person takes the slot nearest the
 * row's centre line (0, +s, −s, +2s, …) that doesn't overlap anyone already
 * placed. Returns a vertical offset per item.
 */
function swarm(items: { x: number; r: number }[], gap = 1.5): number[] {
  const order = items.map((_, idx) => idx).sort((a, b) => items[a].x - items[b].x);
  const placed: { x: number; y: number; r: number }[] = [];
  const out = new Array(items.length).fill(0);
  for (const idx of order) {
    const { x, r } = items[idx];
    const step = r + gap / 2;
    for (let s = 0; s < 4000; s++) {
      const dy = s === 0 ? 0 : (s % 2 ? 1 : -1) * Math.ceil(s / 2) * step;
      let clear = true;
      for (let p = placed.length - 1; p >= 0; p--) {
        const q = placed[p];
        const reach = q.r + r + gap;
        if (x - q.x > reach + 40) break; // placed is x-sorted; nothing further back can touch
        if ((x - q.x) ** 2 + (dy - q.y) ** 2 < reach * reach) {
          clear = false;
          break;
        }
      }
      if (clear) {
        out[idx] = dy;
        // keep `placed` sorted by x for the early break
        let at = placed.length;
        while (at > 0 && placed[at - 1].x > x) at--;
        placed.splice(at, 0, { x, y: dy, r });
        break;
      }
    }
  }
  return out;
}

export function NetworkTree({
  net,
  adj,
  target,
  onTarget,
  onOpenProfile,
}: {
  net: FriendNetwork;
  adj: number[][];
  target: number;
  onTarget: (i: number) => void;
  onOpenProfile: (userId: string) => void;
}) {
  const { nodes, edges } = net;
  const { wrapRef, canvasRef, size } = useCanvasSurface();
  const cameraRef = useRef<Camera>({ x: 0, y: 0, k: 1 });
  const [hover, setHover] = useState<{ i: number; x: number; y: number } | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [history, setHistory] = useState<number[]>([]);

  // Friendship start dates, for "friends since".
  const since = useMemo(() => {
    const m = new Map<number, string | null>();
    for (const [a, b, s] of edges) m.set(a * nodes.length + b, s);
    return m;
  }, [edges, nodes.length]);
  const sinceOf = (a: number, b: number) =>
    since.get(Math.min(a, b) * nodes.length + Math.max(a, b)) ?? null;

  const layout = useMemo(() => {
    const t = target;
    const friends = [...(adj[t] ?? [])];
    const friendSet = new Set(friends);
    const via = new Map<number, number[]>();
    for (const f of friends) {
      for (const n of adj[f]) {
        if (n === t || friendSet.has(n)) continue;
        const list = via.get(n);
        if (list) list.push(f);
        else via.set(n, [f]);
      }
    }
    const allAdjacent = [...via.keys()].sort(
      (a, b) =>
        via.get(b)!.length - via.get(a)!.length ||
        nodes[a].joined.localeCompare(nodes[b].joined) ||
        a - b,
    );
    const adjacent = allAdjacent.slice(0, ADJACENT_CAP);
    const hiddenAdjacent = allAdjacent.length - adjacent.length;

    const lanes: number[][] = [[t], friends, adjacent];
    const visible = new Set<number>(lanes.flat());

    const days = [...visible].map((i) => dayNum(nodes[i].joined));
    let lo = Math.min(...days);
    let hi = Math.max(...days);
    if (hi - lo < 30) {
      const mid = (hi + lo) / 2;
      lo = mid - 15;
      hi = mid + 15;
    }
    const xOf = (d: number) => PAD_X + ((d - lo) / (hi - lo)) * (WORLD_W - 2 * PAD_X);

    const placed = new Map<number, Placed>();
    const laneTop: number[] = [];
    let bottom = 0;
    lanes.forEach((members, laneIdx) => {
      const lane = laneIdx as 0 | 1 | 2;
      const r = RADIUS[lane];
      const xs = members.map((i) => xOf(dayNum(nodes[i].joined)));
      const dys = swarm(xs.map((x) => ({ x, r })));
      const minDy = dys.length ? Math.min(...dys) : 0;
      const maxDy = dys.length ? Math.max(...dys) : 0;
      const centre = laneIdx === 0 ? 0 : bottom + LANE_GAP + (-minDy + r);
      laneTop.push(centre + minDy - r);
      members.forEach((i, idx) => {
        placed.set(i, { i, lane, x: xs[idx], y: centre + dys[idx], r });
      });
      bottom = centre + maxDy + r;
    });

    const shown: Edge[] = [];
    for (const [a, b] of edges) {
      const pa = placed.get(a);
      const pb = placed.get(b);
      if (!pa || !pb) continue;
      const lanesKey = [pa.lane, pb.lane].sort().join("");
      const kind: Edge["kind"] =
        lanesKey === "01" ? "root" : lanesKey === "11" ? "peer" : lanesKey === "12" ? "bridge" : "outer";
      shown.push({ a, b, kind });
    }
    const referrals: [number, number][] = [];
    for (const i of visible) {
      const r = nodes[i].referred_by;
      if (r !== null && visible.has(r)) referrals.push([r, i]);
    }

    const targetDay = dayNum(nodes[t].joined);
    const friendsBefore = friends.filter((f) => dayNum(nodes[f].joined) < targetDay).length;
    const friendsSame = friends.filter((f) => dayNum(nodes[f].joined) === targetDay).length;

    return {
      placed,
      laneTop,
      lanes,
      shown,
      referrals,
      via,
      hiddenAdjacent,
      adjacentTotal: allAdjacent.length,
      friendsBefore,
      friendsSame,
      friendsAfter: friends.length - friendsBefore - friendsSame,
      lo,
      hi,
      xOf,
      bounds: { x0: 0, y0: -RADIUS[0] - 34, x1: WORLD_W, y1: bottom + 20 } as Bounds,
    };
  }, [target, adj, nodes, edges]);

  const fit = (animate: boolean) => {
    if (!size.w) return;
    let cam = cameraToFit(layout.bounds, size.w, size.h - 28, 20, 0.2, 3);
    // On a phone the whole timeline squeezes to unreadable dots: start
    // readable, on the centre person, and let them pan along it.
    if (cam.k < MIN_READABLE_K) {
      const tp = layout.placed.get(target)!;
      const k = MIN_READABLE_K;
      const midY = (layout.bounds.y0 + layout.bounds.y1) / 2;
      cam = { k, x: size.w / 2 - tp.x * k, y: (size.h - 28) / 2 - midY * k };
    }
    if (animate) pz.animateTo(cam);
    else {
      cameraRef.current = cam;
      requestDraw();
    }
  };

  // New centre or new size → frame the whole tree.
  useEffect(() => {
    setSelected(null);
    setHover(null);
  }, [target]);
  useEffect(() => {
    fit(false);
  }, [layout, size.w, size.h]);

  const highlight = hover?.i ?? selected;
  const linked = useMemo(() => {
    if (highlight === null || !layout.placed.has(highlight)) return null;
    const s = new Set<number>([highlight]);
    for (const e of layout.shown) {
      if (e.a === highlight) s.add(e.b);
      if (e.b === highlight) s.add(e.a);
    }
    return s;
  }, [highlight, layout]);

  const draw = () => {
    const canvas = canvasRef.current;
    if (!canvas || !size.w) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const { k, x, y } = cameraRef.current;
    const dpr = size.dpr;
    const { placed, shown, referrals, laneTop, xOf, lo, hi } = layout;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, size.w, size.h);

    const sx = (wx: number) => wx * k + x;
    const sy = (wy: number) => wy * k + y;
    const axisY = size.h - 26;

    // ── Time grid (screen space): ticks chosen so labels sit ≥ 72px apart.
    const visLo = lo + ((((0 - x) / k - PAD_X) / (WORLD_W - 2 * PAD_X)) * (hi - lo));
    const visHi = lo + ((((size.w - x) / k - PAD_X) / (WORLD_W - 2 * PAD_X)) * (hi - lo));
    const pxPerDay = (size.w / Math.max(visHi - visLo, 1));
    const monthsStep = [1, 2, 3, 6, 12, 24].find((m) => m * 30.4 * pxPerDay >= 72) ?? 48;
    const useDays = 7 * pxPerDay >= 72;
    ctx.font = LABEL_FONT(10.5, 600);
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    const ticks: { d: number; label: string }[] = [];
    if (useDays) {
      const start = Math.floor(visLo / 7) * 7 + 4; // Mondays (epoch day 4 = Monday)
      for (let d = start; d <= visHi; d += 7) {
        const dt = new Date(d * 86_400_000);
        ticks.push({
          d,
          label: dt.toLocaleDateString(undefined, { month: "short", day: "numeric", timeZone: "UTC" }),
        });
      }
    } else {
      const s = new Date(visLo * 86_400_000);
      let yy = s.getUTCFullYear();
      let mm = Math.floor(s.getUTCMonth() / monthsStep) * monthsStep;
      for (let guard = 0; guard < 400; guard++) {
        const d = Date.UTC(yy, mm, 1) / 86_400_000;
        if (d > visHi) break;
        if (d >= visLo) {
          const dt = new Date(d * 86_400_000);
          ticks.push({
            d,
            label:
              monthsStep >= 12
                ? String(dt.getUTCFullYear())
                : dt.toLocaleDateString(undefined, { month: "short", year: "2-digit", timeZone: "UTC" }),
          });
        }
        mm += monthsStep;
        if (mm >= 12) {
          yy += Math.floor(mm / 12);
          mm %= 12;
        }
      }
    }
    for (const t of ticks) {
      const tx = sx(xOf(t.d));
      ctx.strokeStyle = "rgba(255,255,255,0.05)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(tx, 0);
      ctx.lineTo(tx, axisY);
      ctx.stroke();
      ctx.fillStyle = "rgba(255,255,255,0.4)";
      ctx.fillText(t.label, tx, axisY + 7);
    }
    ctx.strokeStyle = "rgba(255,255,255,0.12)";
    ctx.beginPath();
    ctx.moveTo(0, axisY + 0.5);
    ctx.lineTo(size.w, axisY + 0.5);
    ctx.stroke();

    // ── The day the centre person joined.
    const tp = placed.get(target)!;
    ctx.setLineDash([4, 4]);
    ctx.strokeStyle = "rgba(255,255,255,0.28)";
    ctx.beginPath();
    ctx.moveTo(sx(tp.x), 0);
    ctx.lineTo(sx(tp.x), axisY);
    ctx.stroke();
    ctx.setLineDash([]);

    // ── Edges (world space).
    ctx.save();
    ctx.setTransform(dpr * k, 0, 0, dpr * k, dpr * x, dpr * y);
    const curve = (a: Placed, b: Placed) => {
      ctx.beginPath();
      if (a.lane === b.lane) {
        // Same row: an arc over the top, taller for longer spans.
        const h = 14 + Math.abs(b.x - a.x) * 0.12;
        ctx.moveTo(a.x, a.y);
        ctx.bezierCurveTo(a.x, a.y - h, b.x, b.y - h, b.x, b.y);
      } else {
        const [top, low] = a.y < b.y ? [a, b] : [b, a];
        const my = (top.y + low.y) / 2;
        ctx.moveTo(top.x, top.y);
        ctx.bezierCurveTo(top.x, my, low.x, my, low.x, low.y);
      }
      ctx.stroke();
    };
    // Friend-to-friend arcs are the densest set (a hub's friends know each
    // other), so they stay faint until someone is hovered.
    const baseAlpha = { root: 0.5, peer: 0.06, bridge: 0.12, outer: 0.04 } as const;
    const targetColor = groupColor(nodes[target].group);
    for (const pass of [0, 1]) {
      for (const e of shown) {
        const on = linked !== null && (e.a === highlight || e.b === highlight);
        if ((pass === 1) !== on) continue;
        const a = placed.get(e.a)!;
        const b = placed.get(e.b)!;
        if (on) {
          ctx.strokeStyle = "rgba(255,255,255,0.8)";
          ctx.lineWidth = 1.6 / k;
        } else {
          const alpha = linked ? Math.min(baseAlpha[e.kind], 0.04) : baseAlpha[e.kind];
          ctx.strokeStyle =
            e.kind === "root" ? withAlpha(targetColor, alpha) : `rgba(255,255,255,${alpha})`;
          ctx.lineWidth = (e.kind === "root" ? 1.4 : 1) / k;
        }
        curve(a, b);
      }
    }
    // Referrals: amber dashed arrows, referrer → the person they brought in.
    ctx.setLineDash([5 / k, 4 / k]);
    ctx.strokeStyle = withAlpha(MAD_WARNING, linked ? 0.35 : 0.8);
    ctx.fillStyle = withAlpha(MAD_WARNING, linked ? 0.35 : 0.9);
    ctx.lineWidth = 1.4 / k;
    for (const [from, to] of referrals) {
      const a = placed.get(from)!;
      const b = placed.get(to)!;
      // Same row: dip UNDER the row (friendships arc over it), so the arrow
      // never runs flat along the row of people.
      const sameRow = a.lane === b.lane;
      const dip = 16 + Math.abs(b.x - a.x) * 0.1;
      const ang = sameRow
        ? -Math.PI / 2 // arrives from below, pointing up into b
        : Math.atan2(b.y - a.y, b.x - a.x);
      const ex = b.x - Math.cos(ang) * (b.r + 2);
      const ey = b.y - Math.sin(ang) * (b.r + 2);
      ctx.beginPath();
      if (sameRow) {
        ctx.moveTo(a.x, a.y + a.r);
        ctx.bezierCurveTo(a.x, a.y + dip, b.x, b.y + dip, ex, ey);
      } else {
        ctx.moveTo(a.x + Math.cos(ang) * a.r, a.y + Math.sin(ang) * a.r);
        ctx.lineTo(ex, ey);
      }
      ctx.stroke();
      ctx.setLineDash([]);
      const s = 6 / k;
      ctx.beginPath();
      ctx.moveTo(ex, ey);
      ctx.lineTo(ex - Math.cos(ang - 0.45) * s, ey - Math.sin(ang - 0.45) * s);
      ctx.lineTo(ex - Math.cos(ang + 0.45) * s, ey - Math.sin(ang + 0.45) * s);
      ctx.closePath();
      ctx.fill();
      ctx.setLineDash([5 / k, 4 / k]);
    }
    ctx.setLineDash([]);

    // ── Nodes.
    for (const p of placed.values()) {
      ctx.globalAlpha = linked && !linked.has(p.i) ? 0.2 : 1;
      ctx.fillStyle = groupColor(nodes[p.i].group);
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
    for (const i of [target, selected, hover?.i]) {
      if (i === null || i === undefined) continue;
      const p = placed.get(i);
      if (!p) continue;
      ctx.strokeStyle = "#ffffff";
      ctx.lineWidth = (i === target ? 2.5 : 2) / k;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r + 2.5 / k, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.restore();

    // ── Labels (screen space).
    const place = labelPlacer();
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    const label = (i: number, force: boolean, fs = 11, weight = 600) => {
      const p = placed.get(i);
      if (!p) return;
      const px = sx(p.x);
      const py = sy(p.y) + p.r * k + 3;
      if (px < -60 || px > size.w + 60 || py < -20 || py > axisY - 4) return;
      ctx.font = LABEL_FONT(fs, weight);
      const text = handle(nodes[i]);
      const w = ctx.measureText(text).width;
      if (!place(px - w / 2 - 2, py, px + w / 2 + 2, py + fs + 2) && !force) return;
      const faded = linked && !linked.has(i);
      haloText(ctx, text, px, py, faded ? "rgba(255,255,255,0.3)" : "rgba(255,255,255,0.92)");
    };
    label(target, true, 13, 800);
    if (hover) label(hover.i, true);
    if (selected !== null) label(selected, true);
    if (linked) for (const i of linked) label(i, false);
    const friendsByCount = [...layout.lanes[1]].sort((a, b) => nodes[b].friends - nodes[a].friends);
    for (const i of friendsByCount) label(i, false);
    if (RADIUS[2] * k >= 4.5) for (const i of layout.lanes[2]) label(i, false, 10.5);

    // ── Row names, pinned to the left edge.
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.font = LABEL_FONT(10.5, 800);
    const counts = [
      "",
      ` · ${layout.lanes[1].length}`,
      ` · ${layout.adjacentTotal}${layout.hiddenAdjacent ? ` (${layout.lanes[2].length} shown)` : ""}`,
    ];
    // Just above each row, so a name never sits on top of a person.
    laneTop.forEach((top, idx) => {
      const py = sy(top) - 12;
      if (py < 8 || py > axisY - 8) return;
      haloText(ctx, `${LANE_NAMES[idx].toUpperCase()}${counts[idx]}`, 10, py, "rgba(255,255,255,0.45)");
    });
  };

  const requestDraw = useRedraw(draw);
  useEffect(requestDraw, [requestDraw, hover, selected, layout, size]);

  const hit = (wx: number, wy: number): number | null => {
    const k = cameraRef.current.k;
    let best: number | null = null;
    let bestD = Infinity;
    for (const p of layout.placed.values()) {
      const d = Math.hypot(p.x - wx, p.y - wy);
      if (d <= p.r + 4 / k && d < bestD) {
        best = p.i;
        bestD = d;
      }
    }
    return best;
  };

  const reroot = (i: number) => {
    if (i === target) return;
    setHistory((h) => [...h.slice(-19), target]);
    onTarget(i);
  };

  const pz = usePanZoom({
    canvasRef,
    cameraRef,
    minK: 0.2,
    maxK: 12,
    onCamera: requestDraw,
    hover: (p) => {
      const el = canvasRef.current;
      if (!p) {
        setHover(null);
        if (el) el.style.cursor = "";
        return;
      }
      const i = hit(p.wx, p.wy);
      if (el) el.style.cursor = i === null ? "grab" : "pointer";
      setHover((h) =>
        i === null ? null : h && h.i === i && Math.abs(h.x - p.sx) < 2 && Math.abs(h.y - p.sy) < 2 ? h : { i, x: p.sx, y: p.sy },
      );
    },
    click: (p) => {
      const i = hit(p.wx, p.wy);
      setSelected((s) => (i === null || i === s ? null : i));
    },
    doubleClick: (p) => {
      const i = hit(p.wx, p.wy);
      if (i !== null) reroot(i);
    },
  });

  const t = nodes[target];
  const hov = hover ? nodes[hover.i] : null;
  const hovPlaced = hover ? layout.placed.get(hover.i) : undefined;
  const sel = selected !== null ? nodes[selected] : null;

  return (
    <div className="rounded-2xl border border-white/[0.08] bg-white/[0.05]">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-3 border-b border-white/[0.08] p-4">
        <div className="min-w-0 flex-1 basis-64">
          <div className="flex items-center gap-2">
            <span className="h-3 w-3 shrink-0 rounded-full" style={{ background: groupColor(t.group) }} />
            <span className="truncate text-[17px] font-extrabold text-white">{handle(t)}</span>
            {t.username && t.name && <span className="truncate text-sm text-white/40">{t.name}</span>}
          </div>
          <p className="mt-1 text-[12.5px] leading-snug text-white/50">
            Joined {dayLabel(t.joined)} · {layout.lanes[1].length} friend{layout.lanes[1].length === 1 ? "" : "s"}:{" "}
            <span className="text-white/75">{layout.friendsBefore} joined before them</span>
            {layout.friendsSame ? `, ${layout.friendsSame} the same day` : ""},{" "}
            <span className="text-white/75">{layout.friendsAfter} after</span> · {layout.adjacentTotal} friends of friends
          </p>
        </div>
        <div className="flex w-full items-center gap-2 sm:w-auto">
          {history.length > 0 && (
            <CanvasButton
              label="Back to the previous person"
              onClick={() => {
                const prev = history[history.length - 1];
                setHistory((h) => h.slice(0, -1));
                onTarget(prev);
              }}
            >
              ← {handle(nodes[history[history.length - 1]])}
            </CanvasButton>
          )}
          <div className="min-w-0 flex-1 sm:w-60">
            <PersonSearch nodes={nodes} onPick={reroot} placeholder="Centre on someone else…" />
          </div>
        </div>
      </div>

      <div ref={wrapRef} className="relative h-[560px] overflow-hidden">
        <canvas
          ref={canvasRef}
          className="absolute inset-0 h-full w-full"
          style={{ touchAction: "none", cursor: "grab" }}
        />
        <div className="absolute top-3 right-3 flex gap-1.5">
          <CanvasButton onClick={() => pz.zoomBy(1.5)} label="Zoom in">+</CanvasButton>
          <CanvasButton onClick={() => pz.zoomBy(1 / 1.5)} label="Zoom out">−</CanvasButton>
          <CanvasButton onClick={() => fit(true)} label="Fit the whole tree">Fit</CanvasButton>
        </div>
        {hov && hover && hovPlaced && (
          <CanvasTooltip x={hover.x} y={hover.y} boxW={size.w} boxH={size.h}>
            <div className="font-semibold text-white">{handle(hov)}</div>
            {hov.username && hov.name && <div className="text-white/50">{hov.name}</div>}
            <div className="mt-1">Joined {dayLabel(hov.joined)}</div>
            {hovPlaced.lane === 0 && <div>{hov.friends} friends · centre of this tree</div>}
            {hovPlaced.lane === 1 && (
              <>
                <div>
                  Friends with {handle(t)}
                  {sinceOf(target, hover.i) ? ` since ${dayLabel(sinceOf(target, hover.i))}` : ""}
                </div>
                <div>
                  {adj[hover.i].filter((n) => layout.placed.get(n)?.lane === 1).length} mutual friends ·{" "}
                  {hov.friends} friends in all
                </div>
              </>
            )}
            {hovPlaced.lane === 2 && (
              <>
                <div className="text-white/50">Not friends with {handle(t)}</div>
                <div>
                  Connected through{" "}
                  {(layout.via.get(hover.i) ?? [])
                    .slice(0, 3)
                    .map((f) => handle(nodes[f]))
                    .join(", ")}
                  {(layout.via.get(hover.i)?.length ?? 0) > 3
                    ? ` +${layout.via.get(hover.i)!.length - 3}`
                    : ""}
                </div>
              </>
            )}
            {hov.referred_by !== null && (
              <div style={{ color: MAD_WARNING }}>Brought in by {handle(nodes[hov.referred_by])}</div>
            )}
          </CanvasTooltip>
        )}
      </div>

      <div className="flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-white/[0.08] px-4 py-3 text-xs text-white/45">
        {sel && selected !== null ? (
          <>
            <span className="text-sm font-semibold text-white/90">{handle(sel)}</span>
            <button
              onClick={() => reroot(selected)}
              className="rounded-full px-3 py-1 text-xs font-semibold text-white"
              style={{ background: "linear-gradient(135deg, #e64d66 0%, #b3334d 100%)" }}
            >
              Centre the tree on them
            </button>
            <button
              onClick={() => onOpenProfile(sel.id)}
              className="rounded-full border border-white/[0.15] px-3 py-1 text-xs font-semibold text-white/80 hover:text-white"
            >
              Profile
            </button>
          </>
        ) : (
          <>
            <span>Left → right: when each person joined. Click to select, double-click to centre the tree on them.</span>
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-0 w-5 border-t border-dashed border-white/50" /> centre person joined
            </span>
            <span className="flex items-center gap-1.5" style={{ color: MAD_WARNING }}>
              <span className="inline-block h-0 w-5 border-t border-dashed" style={{ borderColor: MAD_WARNING }} />{" "}
              brought in (referral)
            </span>
          </>
        )}
      </div>
    </div>
  );
}
