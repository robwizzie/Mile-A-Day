"use client";

/**
 * The friend web: every person with a friend as a dot, every friendship as a
 * line, laid out by a force simulation so friend groups pull together.
 *
 * Groups are the backend's (Louvain over the whole graph), so the colours
 * mean "more connected to each other than to anyone else" and don't reshuffle
 * on reload. Each group is also given a home spot on a spiral (biggest in the
 * middle) that its members are gently pulled toward — without it, the dozens
 * of small disconnected pairs drift off to the edges and every group smears
 * into its neighbours.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  forceCollide,
  forceLink,
  forceManyBody,
  forceSimulation,
  forceX,
  forceY,
  type Simulation,
  type SimulationLinkDatum,
  type SimulationNodeDatum,
} from "d3-force";
import {
  CanvasButton,
  CanvasTooltip,
  cameraToFit,
  daysSince,
  dayLabel,
  groupColor,
  GROUP_COLORS,
  handle,
  haloText,
  LABEL_FONT,
  labelPlacer,
  OTHER_COLOR,
  PersonSearch,
  useCanvasSurface,
  usePanZoom,
  useRedraw,
  withAlpha,
  type Bounds,
  type Camera,
  type FriendNetwork,
} from "./networkCanvas";
import { MAD_RED, MAD_SUCCESS, MAD_WARNING, SegmentedControl } from "./lib";
import { HEAT_HUE } from "./theme";

type SimNode = SimulationNodeDatum & { i: number; r: number; group: number };
type SimLink = SimulationLinkDatum<SimNode> & { same: boolean };

type ColorMode = "group" | "activity" | "joined";

const GOLDEN = Math.PI * (3 - Math.sqrt(5));

/** Deterministic 0..1 noise per index, so the first frame is the same each load. */
const noise = (i: number, salt: number) => {
  const x = Math.sin(i * 12.9898 + salt * 78.233) * 43758.5453;
  return x - Math.floor(x);
};

const nodeRadius = (friends: number) => Math.min(2.5 + Math.sqrt(friends) * 1.5, 16);

export function NetworkWeb({
  net,
  adj,
  onOpenTree,
  onOpenProfile,
}: {
  net: FriendNetwork;
  adj: number[][];
  onOpenTree: (index: number) => void;
  onOpenProfile: (userId: string) => void;
}) {
  const { wrapRef, canvasRef, size } = useCanvasSurface();
  const cameraRef = useRef<Camera>({ x: 0, y: 0, k: 1 });
  const userMovedRef = useRef(false);
  const simRef = useRef<Simulation<SimNode, SimLink> | null>(null);
  const simNodesRef = useRef<SimNode[]>([]);
  const dragRef = useRef<number | null>(null);

  const [hover, setHover] = useState<{ i: number; x: number; y: number } | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [focusGroup, setFocusGroup] = useState<number | null>(null);
  const [mode, setMode] = useState<ColorMode>("group");
  const [labels, setLabels] = useState(true);
  const [expanded, setExpanded] = useState(false);

  const { nodes, edges, groups } = net;

  // Join dates as a 0..1 position (oldest → newest) for the "joined" colouring.
  const joinedT = useMemo(() => {
    if (!nodes.length) return [] as number[];
    const ts = nodes.map((n) => new Date(n.joined).getTime());
    const lo = Math.min(...ts);
    const hi = Math.max(...ts);
    return ts.map((t) => (hi > lo ? (t - lo) / (hi - lo) : 1));
  }, [nodes]);

  const colorOf = useCallback(
    (i: number) => {
      const n = nodes[i];
      if (mode === "group") return groupColor(n.group);
      if (mode === "activity") {
        const d = daysSince(n.last_active);
        if (d !== null && d <= 7) return MAD_SUCCESS;
        if (d !== null && d <= 30) return MAD_WARNING;
        return OTHER_COLOR;
      }
      return `rgba(${HEAT_HUE}, ${0.25 + 0.75 * joinedT[i]})`;
    },
    [nodes, mode, joinedT],
  );

  // Each group's home on a spiral, spaced by area so big groups get room.
  const homes = useMemo(() => {
    let area = 0;
    return groups.map((g, i) => {
      const own = (9 * Math.sqrt(g.size) + 14) ** 2;
      const r = i === 0 ? 0 : 1.05 * Math.sqrt(area + own / 2);
      area += own;
      return { x: Math.cos(i * GOLDEN) * r, y: Math.sin(i * GOLDEN) * r, R: Math.sqrt(own) };
    });
  }, [groups]);

  const bounds = useCallback((only?: (i: number) => boolean): Bounds | null => {
    const sn = simNodesRef.current;
    let b: Bounds | null = null;
    for (const n of sn) {
      if (only && !only(n.i)) continue;
      const x = n.x ?? 0;
      const y = n.y ?? 0;
      if (!b) b = { x0: x - n.r, y0: y - n.r, x1: x + n.r, y1: y + n.r };
      else {
        b.x0 = Math.min(b.x0, x - n.r);
        b.y0 = Math.min(b.y0, y - n.r);
        b.x1 = Math.max(b.x1, x + n.r);
        b.y1 = Math.max(b.y1, y + n.r);
      }
    }
    return b;
  }, []);

  // Label priority: the most connected first.
  const byFriends = useMemo(
    () => nodes.map((_, i) => i).sort((a, b) => nodes[b].friends - nodes[a].friends),
    [nodes],
  );

  const neighbours = useMemo(
    () => (selected === null ? null : new Set(adj[selected] ?? [])),
    [selected, adj],
  );

  // ─── Draw ───
  const draw = () => {
    const canvas = canvasRef.current;
    if (!canvas || !size.w) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const { k, x, y } = cameraRef.current;
    const sn = simNodesRef.current;
    const dpr = size.dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, size.w, size.h);

    const dimmed = (i: number) => {
      if (selected !== null) return i !== selected && !neighbours!.has(i);
      if (focusGroup !== null) return nodes[i].group !== focusGroup;
      return false;
    };

    ctx.setTransform(dpr * k, 0, 0, dpr * k, dpr * x, dpr * y);
    ctx.lineWidth = 1 / k;

    // Edges: one batched path for the background, then the highlighted ones.
    const quiet = selected !== null || focusGroup !== null;
    ctx.strokeStyle = quiet ? "rgba(255,255,255,0.035)" : "rgba(255,255,255,0.11)";
    ctx.beginPath();
    for (const [a, b] of edges) {
      const na = sn[a];
      const nb = sn[b];
      if (!na || !nb) continue;
      ctx.moveTo(na.x!, na.y!);
      ctx.lineTo(nb.x!, nb.y!);
    }
    ctx.stroke();

    if (quiet) {
      ctx.lineWidth = 1.4 / k;
      for (const [a, b] of edges) {
        let on = false;
        let color = "rgba(255,255,255,0.55)";
        if (selected !== null) on = a === selected || b === selected;
        else if (focusGroup !== null) {
          on = nodes[a].group === focusGroup && nodes[b].group === focusGroup;
          color = withAlpha(groupColor(focusGroup), 0.45);
        }
        if (!on) continue;
        ctx.strokeStyle = color;
        ctx.beginPath();
        ctx.moveTo(sn[a].x!, sn[a].y!);
        ctx.lineTo(sn[b].x!, sn[b].y!);
        ctx.stroke();
      }
    }

    // Nodes. Never smaller than ~1.5px on screen, or zoomed-out singletons vanish.
    for (const n of sn) {
      const r = Math.max(n.r, 1.6 / k);
      ctx.globalAlpha = dimmed(n.i) ? 0.13 : 1;
      ctx.fillStyle = colorOf(n.i);
      ctx.beginPath();
      ctx.arc(n.x!, n.y!, r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
    for (const i of [selected, hover?.i]) {
      if (i === null || i === undefined || !sn[i]) continue;
      ctx.strokeStyle = "#ffffff";
      ctx.lineWidth = 2 / k;
      ctx.beginPath();
      ctx.arc(sn[i].x!, sn[i].y!, Math.max(sn[i].r, 1.6 / k) + 2.5 / k, 0, Math.PI * 2);
      ctx.stroke();
    }

    // Text in screen space.
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    const place = labelPlacer();
    const toScreen = (n: SimNode) => ({ sx: n.x! * k + x, sy: n.y! * k + y });

    // Priority people first, so a busy area never hides the one you clicked.
    const priority: number[] = [];
    if (selected !== null) priority.push(selected, ...adj[selected]);
    if (hover) priority.unshift(hover.i);
    ctx.font = LABEL_FONT(11);
    let drawn = 0;
    const labelNode = (i: number, force: boolean) => {
      const n = sn[i];
      if (!n) return;
      const { sx, sy } = toScreen(n);
      if (sx < -50 || sx > size.w + 50 || sy < -20 || sy > size.h + 20) return;
      const text = handle(nodes[i]);
      const w = ctx.measureText(text).width;
      const top = sy + Math.max(n.r * k, 1.6) + 3;
      if (!place(sx - w / 2 - 2, top, sx + w / 2 + 2, top + 13) && !force) return;
      haloText(ctx, text, sx, top, dimmed(i) ? "rgba(255,255,255,0.35)" : "rgba(255,255,255,0.9)");
      drawn++;
    };
    for (const i of priority) labelNode(i, i === selected || i === hover?.i);

    // Group names while zoomed out: what each cluster IS, not 300 usernames.
    const showGroupNames = selected === null && k < 1.6;
    if (showGroupNames) {
      ctx.font = LABEL_FONT(12.5, 800);
      const centroid = new Map<number, { x: number; y: number; n: number }>();
      for (const n of sn) {
        if (n.group >= 12 || groups[n.group].size < 4) continue;
        const c = centroid.get(n.group) ?? { x: 0, y: 0, n: 0 };
        c.x += n.x!;
        c.y += n.y!;
        c.n += 1;
        centroid.set(n.group, c);
      }
      for (const [g, c] of [...centroid.entries()].sort((a, b) => a[0] - b[0])) {
        if (focusGroup !== null && g !== focusGroup) continue;
        const sx = (c.x / c.n) * k + x;
        const sy = (c.y / c.n) * k + y;
        const hub = nodes[groups[g].hub];
        const text = `${handle(hub)}'s group · ${groups[g].size}`;
        const w = ctx.measureText(text).width;
        if (!place(sx - w / 2 - 3, sy - 8, sx + w / 2 + 3, sy + 10)) continue;
        ctx.textBaseline = "middle";
        haloText(ctx, text, sx, sy, mode === "group" ? groupColor(g) : "rgba(255,255,255,0.85)");
        ctx.textBaseline = "top";
      }
    }

    if (labels) {
      ctx.font = LABEL_FONT(11);
      for (let rank = 0; rank < byFriends.length && drawn < 140; rank++) {
        const n = sn[byFriends[rank]];
        if (!n) continue;
        // Hubs always try; everyone else once they're big enough on screen.
        if (rank >= 10 && n.r * k < 4.5) continue;
        if (showGroupNames && rank >= 10) continue;
        labelNode(n.i, false);
      }
    }
  };

  const requestDraw = useRedraw(draw);

  // Redraw whenever anything the picture depends on changes.
  useEffect(requestDraw, [requestDraw, selected, hover, focusGroup, mode, labels, size]);

  // A declaration, not a const: the pan/zoom handlers below call it, and it
  // calls back into them.
  function fitTo(b: Bounds | null, animate: boolean, maxK = 2.5) {
    if (!b || !size.w) return;
    const cam = cameraToFit(b, size.w, size.h, 36, 0.05, maxK);
    if (animate) pz.animateTo(cam);
    else {
      cameraRef.current = cam;
      requestDraw();
    }
  }

  // A resize (or going full screen) keeps whatever was in the middle, in the
  // middle — or re-frames everyone if the user hasn't taken the camera yet.
  const prevSize = useRef(size);
  useEffect(() => {
    const prev = prevSize.current;
    prevSize.current = size;
    if (!size.w || !prev.w || (prev.w === size.w && prev.h === size.h)) return;
    const c = cameraRef.current;
    if (!userMovedRef.current) {
      const b = bounds();
      if (b) cameraRef.current = cameraToFit(b, size.w, size.h, 36, 0.05, 2.5);
    } else {
      c.x += (size.w - prev.w) / 2;
      c.y += (size.h - prev.h) / 2;
    }
    requestDraw();
  }, [size, bounds, requestDraw]);

  // ─── Simulation ───
  useEffect(() => {
    const simNodes: SimNode[] = nodes.map((n, i) => {
      const h = homes[n.group] ?? { x: 0, y: 0, R: 20 };
      const a = noise(i, 1) * Math.PI * 2;
      const d = Math.sqrt(noise(i, 2)) * h.R;
      return {
        i,
        r: nodeRadius(n.friends),
        group: n.group,
        x: h.x + Math.cos(a) * d,
        y: h.y + Math.sin(a) * d,
      };
    });
    const links: SimLink[] = edges.map(([a, b]) => ({
      source: a,
      target: b,
      same: nodes[a].group === nodes[b].group,
    }));
    simNodesRef.current = simNodes;
    userMovedRef.current = false;

    const sim = forceSimulation<SimNode, SimLink>(simNodes)
      .force(
        "link",
        forceLink<SimNode, SimLink>(links).distance((l) => (l.same ? 24 : 70)),
      )
      .force("charge", forceManyBody<SimNode>().strength(-28).distanceMax(280))
      .force("collide", forceCollide<SimNode>((d) => d.r + 1.2).iterations(1))
      .force("x", forceX<SimNode>((d) => homes[d.group]?.x ?? 0).strength(0.045))
      .force("y", forceY<SimNode>((d) => homes[d.group]?.y ?? 0).strength(0.045))
      .alphaDecay(0.028)
      .on("tick", () => {
        // Keep the whole web framed while it settles, until the user takes
        // the camera — then it's theirs.
        if (!userMovedRef.current) {
          const b = bounds();
          const el = canvasRef.current;
          if (b && el && el.clientWidth) {
            cameraRef.current = cameraToFit(b, el.clientWidth, el.clientHeight, 36, 0.05, 2.5);
          }
        }
        requestDraw();
      });
    simRef.current = sim;
    return () => {
      sim.stop();
      simRef.current = null;
    };
  }, [nodes, edges, homes, bounds, canvasRef, requestDraw]);

  const hit = (wx: number, wy: number): number | null => {
    const k = cameraRef.current.k;
    let best: number | null = null;
    let bestD = Infinity;
    for (const n of simNodesRef.current) {
      const d = Math.hypot(n.x! - wx, n.y! - wy);
      const reach = Math.max(n.r, 1.6 / k) + 5 / k;
      if (d <= reach && d < bestD) {
        best = n.i;
        bestD = d;
      }
    }
    return best;
  };

  const pz = usePanZoom({
    canvasRef,
    cameraRef,
    minK: 0.05,
    maxK: 8,
    onCamera: (byUser) => {
      if (byUser) userMovedRef.current = true;
      requestDraw();
    },
    grab: (p) => {
      const i = hit(p.wx, p.wy);
      if (i === null) return false;
      dragRef.current = i;
      return true;
    },
    drag: (p) => {
      const i = dragRef.current;
      if (i === null) return;
      const n = simNodesRef.current[i];
      n.fx = p.wx;
      n.fy = p.wy;
      userMovedRef.current = true;
      simRef.current?.alphaTarget(0.25).restart();
    },
    release: () => {
      const i = dragRef.current;
      if (i !== null) {
        const n = simNodesRef.current[i];
        n.fx = null;
        n.fy = null;
      }
      dragRef.current = null;
      simRef.current?.alphaTarget(0);
    },
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
      if (i === null) return;
      setSelected(i);
      const set = new Set([i, ...adj[i]]);
      fitTo(bounds((j) => set.has(j)), true, 4);
    },
  });

  // Esc leaves full screen.
  useEffect(() => {
    if (!expanded) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setExpanded(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [expanded]);

  const selectAndShow = (i: number) => {
    setFocusGroup(null);
    setSelected(i);
    const n = simNodesRef.current[i];
    if (!n || !size.w) return;
    const k = Math.max(cameraRef.current.k, 1.8);
    userMovedRef.current = true;
    pz.animateTo({ k, x: size.w / 2 - n.x! * k, y: size.h / 2 - n.y! * k });
  };

  const focus = (g: number | null) => {
    setSelected(null);
    setFocusGroup(g);
    userMovedRef.current = true;
    fitTo(g === null ? bounds() : bounds((j) => nodes[j].group === g), true, 4);
  };

  const sel = selected !== null ? nodes[selected] : null;
  const hov = hover ? nodes[hover.i] : null;
  const topGroups = groups.slice(0, 10);

  return (
    <div
      className={
        expanded
          ? "fixed inset-0 z-[45] flex flex-col gap-3 bg-[#0a0a0a] p-3 sm:p-4"
          : "rounded-2xl border border-white/[0.08] bg-white/[0.05]"
      }
    >
      <div className={`flex min-h-0 flex-1 flex-col lg:flex-row ${expanded ? "gap-3" : ""}`}>
        {/* Canvas */}
        <div
          ref={wrapRef}
          // flex-1 only where it's the ROW axis (or full screen): in the
          // phone column, a flex-basis of 0 overrides the fixed height and the
          // canvas collapses to nothing.
          className={`relative min-w-0 overflow-hidden ${
            expanded
              ? "min-h-[60vh] flex-1 rounded-2xl border border-white/[0.08]"
              : "h-[min(640px,72vh)] shrink-0 rounded-t-2xl lg:flex-1 lg:rounded-l-2xl lg:rounded-tr-none"
          }`}
        >
          <canvas
            ref={canvasRef}
            className="absolute inset-0 h-full w-full"
            style={{ touchAction: "none", cursor: "grab" }}
          />
          <div className="absolute top-3 right-3 flex flex-wrap justify-end gap-1.5">
            <CanvasButton onClick={() => pz.zoomBy(1.5)} label="Zoom in">+</CanvasButton>
            <CanvasButton onClick={() => pz.zoomBy(1 / 1.5)} label="Zoom out">−</CanvasButton>
            <CanvasButton onClick={() => focus(null)} label="Fit everyone">Fit</CanvasButton>
            <CanvasButton onClick={() => setLabels((v) => !v)} label="Show names" active={labels}>
              Names
            </CanvasButton>
            <CanvasButton
              onClick={() => simRef.current?.alpha(0.6).restart()}
              label="Re-run the layout"
            >
              Shake
            </CanvasButton>
            <CanvasButton
              onClick={() => setExpanded((v) => !v)}
              label={expanded ? "Exit full screen (Esc)" : "Full screen"}
            >
              {expanded ? "Close" : "Expand"}
            </CanvasButton>
          </div>
          <div className="pointer-events-none absolute right-3 bottom-2.5 left-3 hidden truncate text-[11px] text-white/30 sm:block">
            Drag to move · scroll or pinch to zoom · click a person · double-click to zoom to their friends
          </div>
          {hov && hover && (
            <CanvasTooltip x={hover.x} y={hover.y} boxW={size.w} boxH={size.h}>
              <div className="font-semibold text-white">{handle(hov)}</div>
              {hov.username && hov.name && <div className="text-white/50">{hov.name}</div>}
              <div className="mt-1">
                {hov.friends} friend{hov.friends === 1 ? "" : "s"} ·{" "}
                <span style={{ color: groupColor(hov.group) }}>
                  {handle(nodes[groups[hov.group].hub])}&apos;s group
                </span>
              </div>
              <div>Joined {dayLabel(hov.joined)}</div>
              <div>
                Last walk:{" "}
                {hov.last_active ? `${dayLabel(hov.last_active)} (${daysSince(hov.last_active)}d ago)` : "never"}
              </div>
            </CanvasTooltip>
          )}
        </div>

        {/* Side panel */}
        <aside
          className={`flex w-full shrink-0 flex-col gap-4 p-4 lg:w-72 ${
            expanded
              ? "rounded-2xl border border-white/[0.08] bg-white/[0.05]"
              : "border-t border-white/[0.08] lg:max-h-[min(640px,72vh)] lg:border-t-0 lg:border-l"
          }`}
        >
          {/* Outside the scrolling part, so its dropdown isn't clipped. */}
          <PersonSearch nodes={nodes} onPick={selectAndShow} />
          <div className="flex min-h-0 flex-col gap-4 lg:-mr-2 lg:overflow-y-auto lg:pr-2">

          {sel && selected !== null ? (
            <div className="rounded-xl border border-white/[0.1] bg-white/[0.04] p-3">
              <div className="flex items-center gap-2">
                <span className="h-3 w-3 shrink-0 rounded-full" style={{ background: groupColor(sel.group) }} />
                <span className="min-w-0 flex-1 truncate font-bold text-white">{handle(sel)}</span>
                <button
                  onClick={() => setSelected(null)}
                  className="text-white/35 hover:text-white"
                  aria-label="Clear selection"
                >
                  ✕
                </button>
              </div>
              {sel.username && sel.name && <div className="mt-0.5 text-xs text-white/45">{sel.name}</div>}
              <dl className="mt-2.5 grid grid-cols-2 gap-x-3 gap-y-1.5 text-xs">
                <dt className="text-white/40">Friends</dt>
                <dd className="text-right tabular-nums text-white/85">{sel.friends}</dd>
                <dt className="text-white/40">Joined</dt>
                <dd className="text-right text-white/85">{dayLabel(sel.joined)}</dd>
                <dt className="text-white/40">Last walk</dt>
                <dd className="text-right text-white/85">{sel.last_active ? dayLabel(sel.last_active) : "never"}</dd>
                <dt className="text-white/40">Group</dt>
                <dd className="truncate text-right" style={{ color: groupColor(sel.group) }}>
                  {handle(nodes[groups[sel.group].hub])}&apos;s · {groups[sel.group].size}
                </dd>
                {sel.referred_by !== null && (
                  <>
                    <dt className="text-white/40">Brought in by</dt>
                    <dd className="truncate text-right">
                      <button className="text-white/85 hover:text-white" onClick={() => selectAndShow(sel.referred_by!)}>
                        {handle(nodes[sel.referred_by])}
                      </button>
                    </dd>
                  </>
                )}
              </dl>
              <div className="mt-3 grid grid-cols-2 gap-1.5">
                <button
                  onClick={() => {
                    setExpanded(false);
                    onOpenTree(selected);
                  }}
                  className="rounded-full px-3 py-1.5 text-xs font-semibold text-white"
                  style={{ background: "linear-gradient(135deg, #e64d66 0%, #b3334d 100%)" }}
                >
                  Friend tree
                </button>
                <button
                  onClick={() => onOpenProfile(sel.id)}
                  className="rounded-full border border-white/[0.15] px-3 py-1.5 text-xs font-semibold text-white/80 hover:border-white/30 hover:text-white"
                >
                  Profile
                </button>
                <button
                  onClick={() => focus(sel.group)}
                  className="col-span-2 rounded-full border border-white/[0.1] px-3 py-1.5 text-xs font-semibold text-white/60 hover:text-white"
                >
                  Show their whole group
                </button>
              </div>
            </div>
          ) : null}

          <div>
            <div className="mb-2 text-[11px] font-semibold tracking-[0.4px] text-white/45 uppercase">
              Colour by
            </div>
            <SegmentedControl
              value={mode}
              onChange={setMode}
              options={[
                { value: "group", label: "Group" },
                { value: "activity", label: "Activity" },
                { value: "joined", label: "Joined" },
              ]}
            />
            {mode === "activity" && (
              <ul className="mt-2.5 space-y-1 text-xs text-white/60">
                <LegendRow color={MAD_SUCCESS} label="Walked in the last 7 days" />
                <LegendRow color={MAD_WARNING} label="Walked in the last 30 days" />
                <LegendRow color={OTHER_COLOR} label="Quiet for 30+ days" />
              </ul>
            )}
            {mode === "joined" && (
              <div className="mt-2.5 text-xs text-white/55">
                <div
                  className="h-2 rounded-full"
                  style={{ background: `linear-gradient(90deg, rgba(${HEAT_HUE},0.25), ${MAD_RED})` }}
                />
                <div className="mt-1 flex justify-between">
                  <span>First to join</span>
                  <span>Newest</span>
                </div>
              </div>
            )}
          </div>

          <div className="min-h-0">
            <div className="mb-2 flex items-baseline justify-between">
              <span className="text-[11px] font-semibold tracking-[0.4px] text-white/45 uppercase">
                Friend groups
              </span>
              {focusGroup !== null && (
                <button onClick={() => focus(null)} className="text-xs text-white/50 hover:text-white">
                  Show all
                </button>
              )}
            </div>
            <ul className="space-y-0.5">
              {topGroups.map((g) => (
                <li key={g.id}>
                  <button
                    onClick={() => focus(focusGroup === g.id ? null : g.id)}
                    className={`flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm transition ${
                      focusGroup === g.id ? "bg-white/[0.09]" : "hover:bg-white/[0.05]"
                    }`}
                  >
                    <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: groupColor(g.id) }} />
                    <span className="min-w-0 flex-1 truncate text-white/85">
                      {handle(nodes[g.hub])}&apos;s
                    </span>
                    <span className="shrink-0 text-xs tabular-nums text-white/45">
                      {g.size} · <span className="text-[#7fe39a]">{g.active_7d}</span>
                    </span>
                  </button>
                </li>
              ))}
            </ul>
            <p className="mt-2 text-[11px] leading-snug text-white/35">
              People · <span className="text-[#7fe39a]">walked this week</span>. Named for the member with the most
              friends inside it. The {GROUP_COLORS.length} biggest are in colour
              {groups.length > GROUP_COLORS.length
                ? `; the other ${groups.length - GROUP_COLORS.length} are grey`
                : ""}
              {groups.length > topGroups.length ? ` (${groups.length - topGroups.length} not listed)` : ""}.
            </p>
          </div>
          </div>
        </aside>
      </div>
    </div>
  );
}

function LegendRow({ color, label }: { color: string; label: string }) {
  return (
    <li className="flex items-center gap-2">
      <span className="h-2.5 w-2.5 rounded-full" style={{ background: color }} />
      {label}
    </li>
  );
}
