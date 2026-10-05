"use client";

/**
 * Where people walk, as a heatmap over a world map.
 *
 * The backend sends grid CELLS (≈17-mile squares) with a head count each —
 * never a person's coordinates — and a person's cell is where their recent
 * GPS routes mostly run. So this is "where the app is used", at city scale,
 * and it can only ever show people who have walked with GPS on.
 *
 * Drawn as a classic heatmap: every cell stamps a soft blob into an offscreen
 * buffer, and the accumulated density is coloured through one red ramp.
 * Blobs keep a fixed SCREEN size, so zooming in pulls a city's blob apart
 * into its cells; once a cell is big enough on screen it gets a dot and its
 * count.
 */

import { useEffect, useMemo, useRef, useState } from "react";
import { geoBounds, geoContains, geoMercator, geoPath } from "d3-geo";
import { feature } from "topojson-client";
import type { Feature, FeatureCollection, Geometry } from "geojson";
import type { GeometryCollection, Topology } from "topojson-specification";
import {
  CanvasButton,
  CanvasTooltip,
  cameraToFit,
  haloText,
  LABEL_FONT,
  useCanvasSurface,
  usePanZoom,
  useRedraw,
  type Bounds,
  type Camera,
  type UserLocations,
} from "./networkCanvas";
import { BarList, fmt, MAD_RED, SegmentedControl } from "./lib";
import { MAD_RED_DEEP } from "./theme";

const WORLD_W = 1000;
/** Heat buffer resolution vs CSS px. The blobs are soft, so half is plenty. */
const HEAT_SCALE = 0.5;
/** Density ramp: the app's deep red → madRed → the dashboard's highlight pink → white-hot. */
const RAMP = [
  [0, MAD_RED_DEEP],
  [0.45, MAD_RED],
  [0.8, "#ffb3c6"],
  [1, "#ffffff"],
] as const;

type Country = { name: string; path: Path2D; feature: Feature<Geometry>; bbox: [[number, number], [number, number]] };

const projection = geoMercator()
  .scale(WORLD_W / (2 * Math.PI))
  .translate([WORLD_W / 2, WORLD_W / 2]);
const project = (lng: number, lat: number) => projection([lng, lat]) ?? [0, 0];
const [, NORTH] = project(0, 84);
const [, SOUTH] = project(0, -58);
const WORLD: Bounds = { x0: 0, y0: NORTH, x1: WORLD_W, y1: SOUTH };

/** 256-entry colour lookup for the density ramp. */
function rampLut(): Uint8ClampedArray {
  const c = document.createElement("canvas");
  c.width = 256;
  c.height = 1;
  const g = c.getContext("2d")!;
  const grad = g.createLinearGradient(0, 0, 256, 0);
  for (const [at, color] of RAMP) grad.addColorStop(at, color);
  g.fillStyle = grad;
  g.fillRect(0, 0, 256, 1);
  return g.getImageData(0, 0, 256, 1).data;
}

function inBox(b: Country["bbox"], lng: number, lat: number) {
  const [[w, s], [e, n]] = b;
  if (lat < s || lat > n) return false;
  // A box crossing the antimeridian has west > east.
  return w <= e ? lng >= w && lng <= e : lng >= w || lng <= e;
}

function countryAt(countries: Country[], lng: number, lat: number): string | null {
  for (const c of countries) {
    if (inBox(c.bbox, lng, lat) && geoContains(c.feature, [lng, lat])) return c.name;
  }
  return null;
}

const offsetLabel = (m: number | null) => {
  if (m === null) return "Never reported";
  const sign = m < 0 ? "−" : "+";
  const a = Math.abs(m);
  return `UTC${sign}${Math.floor(a / 60)}${a % 60 ? `:${String(a % 60).padStart(2, "0")}` : ""}`;
};

export function NetworkMap({ loc }: { loc: UserLocations }) {
  const { wrapRef, canvasRef, size } = useCanvasSurface();
  const cameraRef = useRef<Camera>({ x: 0, y: 0, k: 1 });
  const heatRef = useRef<HTMLCanvasElement | null>(null);
  const lutRef = useRef<Uint8ClampedArray | null>(null);
  const [countries, setCountries] = useState<Country[] | null>(null);
  const [metric, setMetric] = useState<"users" | "active">("users");
  const [hover, setHover] = useState<{ c: number; x: number; y: number } | null>(null);
  const placedRef = useRef(false);

  // The atlas is ~750KB: load it only when this panel mounts.
  useEffect(() => {
    let live = true;
    import("world-atlas/countries-50m.json").then((mod) => {
      if (!live) return;
      const topo = (mod.default ?? mod) as unknown as Topology<{ countries: GeometryCollection<{ name: string }> }>;
      const fc = feature(topo, topo.objects.countries) as FeatureCollection<Geometry, { name: string }>;
      const path = geoPath(projection);
      setCountries(
        fc.features
          .filter((f) => f.properties?.name !== "Antarctica")
          .map((f) => ({
            name: f.properties?.name ?? "Unknown",
            path: new Path2D(path(f) ?? ""),
            feature: f,
            bbox: geoBounds(f) as Country["bbox"],
          })),
      );
    });
    return () => {
      live = false;
    };
  }, []);

  const cells = useMemo(
    () =>
      loc.cells
        .map((c) => {
          const [px, py] = project(c.lng, c.lat);
          return { ...c, px, py, value: metric === "users" ? c.users : c.active };
        })
        .filter((c) => c.value > 0),
    [loc.cells, metric],
  );

  // Country per cell, once the atlas is in. A coastal city's cell centre can
  // land just offshore at this resolution, so try a ring of nearby points
  // before giving up.
  const cellCountry = useMemo(() => {
    if (!countries) return null;
    return loc.cells.map((c) => {
      const d = loc.cell_degrees * 0.6;
      for (const [dx, dy] of [[0, 0], [d, 0], [-d, 0], [0, d], [0, -d], [d, d], [-d, -d], [d, -d], [-d, d]]) {
        const name = countryAt(countries, c.lng + dx, c.lat + dy);
        if (name) return name;
      }
      return null;
    });
  }, [countries, loc.cells, loc.cell_degrees]);

  const byCountry = useMemo(() => {
    if (!cellCountry) return null;
    const m = new Map<string, { users: number; cells: number[] }>();
    loc.cells.forEach((c, idx) => {
      const v = metric === "users" ? c.users : c.active;
      if (!v) return;
      const name = cellCountry[idx] ?? "Unplaced (at sea)";
      const e = m.get(name) ?? { users: 0, cells: [] };
      e.users += v;
      e.cells.push(idx);
      m.set(name, e);
    });
    return [...m.entries()].sort((a, b) => b[1].users - a[1].users);
  }, [cellCountry, loc.cells, metric]);

  const draw = () => {
    const canvas = canvasRef.current;
    if (!canvas || !size.w) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const { k, x, y } = cameraRef.current;
    const dpr = size.dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, size.w, size.h);

    // Land.
    if (countries) {
      ctx.setTransform(dpr * k, 0, 0, dpr * k, dpr * x, dpr * y);
      ctx.fillStyle = "rgba(255,255,255,0.055)";
      ctx.strokeStyle = "rgba(255,255,255,0.13)";
      ctx.lineWidth = 0.7 / k;
      for (const c of countries) {
        ctx.fill(c.path);
        ctx.stroke(c.path);
      }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    // Heat.
    const cellPx = loc.cell_degrees * (WORLD_W / 360) * k;
    const R = Math.max(15, cellPx * 0.9);
    const hw = Math.max(1, Math.round(size.w * HEAT_SCALE));
    const hh = Math.max(1, Math.round(size.h * HEAT_SCALE));
    let heat = heatRef.current;
    if (!heat) heat = heatRef.current = document.createElement("canvas");
    if (heat.width !== hw || heat.height !== hh) {
      heat.width = hw;
      heat.height = hh;
    }
    const h = heat.getContext("2d", { willReadFrequently: true });
    if (h && cells.length) {
      h.clearRect(0, 0, hw, hh);
      const r = R * HEAT_SCALE;
      const stamp = document.createElement("canvas");
      stamp.width = stamp.height = Math.ceil(r * 2);
      const s = stamp.getContext("2d")!;
      const g = s.createRadialGradient(r, r, 0, r, r, r);
      g.addColorStop(0, "rgba(0,0,0,1)");
      g.addColorStop(1, "rgba(0,0,0,0)");
      s.fillStyle = g;
      s.fillRect(0, 0, r * 2, r * 2);
      const max = Math.max(...cells.map((c) => c.value), 1);
      for (const c of cells) {
        const px = (c.px * k + x) * HEAT_SCALE;
        const py = (c.py * k + y) * HEAT_SCALE;
        if (px < -r || py < -r || px > hw + r || py > hh + r) continue;
        h.globalAlpha = 0.3 + 0.7 * (Math.log1p(c.value) / Math.log1p(max));
        h.drawImage(stamp, px - r, py - r);
      }
      h.globalAlpha = 1;
      const img = h.getImageData(0, 0, hw, hh);
      const lut = (lutRef.current ??= rampLut());
      const d = img.data;
      for (let p = 0; p < d.length; p += 4) {
        const a = d[p + 3];
        if (!a) continue;
        const o = a * 4;
        d[p] = lut[o];
        d[p + 1] = lut[o + 1];
        d[p + 2] = lut[o + 2];
        d[p + 3] = Math.min(255, 40 + a * 1.3);
      }
      h.putImageData(img, 0, 0);
      ctx.imageSmoothingEnabled = true;
      ctx.drawImage(heat, 0, 0, size.w, size.h);
    }

    // Close in, each cell gets a dot — and a number once there's room.
    if (cellPx >= 5) {
      ctx.textAlign = "center";
      ctx.textBaseline = "bottom";
      ctx.font = LABEL_FONT(11, 700);
      for (const c of cells) {
        const sx = c.px * k + x;
        const sy = c.py * k + y;
        if (sx < -20 || sy < -20 || sx > size.w + 20 || sy > size.h + 20) continue;
        ctx.fillStyle = "rgba(255,255,255,0.9)";
        ctx.beginPath();
        ctx.arc(sx, sy, 2.5, 0, Math.PI * 2);
        ctx.fill();
        if (cellPx >= 22) haloText(ctx, fmt(c.value), sx, sy - 5, "#ffffff");
      }
    }
  };

  const requestDraw = useRedraw(draw);
  useEffect(requestDraw, [requestDraw, countries, cells, size]);

  const fitWorld = (animate: boolean) => {
    if (!size.w) return;
    const cam = cameraToFit(WORLD, size.w, size.h, 8, 0.5, 80);
    if (animate) pz.animateTo(cam);
    else {
      cameraRef.current = cam;
      requestDraw();
    }
  };
  const fitCells = (idxs?: number[]) => {
    const pts = (idxs ? idxs.map((i) => loc.cells[i]) : loc.cells).map((c) => project(c.lng, c.lat));
    if (!pts.length || !size.w) return;
    const pad = 12;
    const b: Bounds = {
      x0: Math.min(...pts.map((p) => p[0])) - pad,
      y0: Math.min(...pts.map((p) => p[1])) - pad,
      x1: Math.max(...pts.map((p) => p[0])) + pad,
      y1: Math.max(...pts.map((p) => p[1])) + pad,
    };
    pz.animateTo(cameraToFit(b, size.w, size.h, 40, 0.5, 60));
  };

  // First frame shows the whole world; later resizes keep the view.
  useEffect(() => {
    if (!size.w) return;
    if (!placedRef.current) {
      placedRef.current = true;
      fitWorld(false);
    } else requestDraw();
  }, [size.w, size.h]);

  const hit = (sx: number, sy: number): number | null => {
    const { k, x, y } = cameraRef.current;
    const cellPx = loc.cell_degrees * (WORLD_W / 360) * k;
    const reach = Math.max(10, cellPx * 0.6);
    let best: number | null = null;
    let bestD = Infinity;
    cells.forEach((c, i) => {
      const d = Math.hypot(c.px * k + x - sx, c.py * k + y - sy);
      if (d <= reach && d < bestD) {
        best = i;
        bestD = d;
      }
    });
    return best;
  };

  const pz = usePanZoom({
    canvasRef,
    cameraRef,
    minK: 0.5,
    maxK: 80,
    onCamera: requestDraw,
    hover: (p) => {
      if (!p) return setHover(null);
      const c = hit(p.sx, p.sy);
      const el = canvasRef.current;
      if (el) el.style.cursor = c === null ? "grab" : "default";
      setHover(c === null ? null : { c, x: p.sx, y: p.sy });
    },
    doubleClick: (p) => {
      const c = cameraRef.current;
      const k = Math.min(80, c.k * 2.5);
      pz.animateTo({ k, x: p.sx - p.wx * k, y: p.sy - p.wy * k }, 400);
    },
  });

  const hc = hover ? cells[hover.c] : null;
  const hcIdx = hc ? loc.cells.findIndex((c) => c.lat === hc.lat && c.lng === hc.lng) : -1;
  const s = loc.summary;
  const located = metric === "users" ? s.located_users : s.active_located_users;

  return (
    <div className="flex flex-col overflow-hidden rounded-2xl border border-white/[0.08] bg-white/[0.05] lg:flex-row">
      <div ref={wrapRef} className="relative h-[min(560px,70vh)] min-w-0 shrink-0 lg:flex-1">
        <canvas
          ref={canvasRef}
          className="absolute inset-0 h-full w-full"
          style={{ touchAction: "none", cursor: "grab" }}
        />
        <div className="absolute top-3 right-3 flex gap-1.5">
          <CanvasButton onClick={() => pz.zoomBy(1.6)} label="Zoom in">+</CanvasButton>
          <CanvasButton onClick={() => pz.zoomBy(1 / 1.6)} label="Zoom out">−</CanvasButton>
          <CanvasButton onClick={() => fitWorld(true)} label="Whole world">World</CanvasButton>
          <CanvasButton onClick={() => fitCells()} label="Zoom to where people are">People</CanvasButton>
        </div>
        {!countries && (
          <div className="absolute bottom-3 left-3 text-xs text-white/35">Loading map…</div>
        )}
        {cells.length === 0 && (
          <div className="absolute inset-0 flex items-center justify-center text-sm text-white/40">
            No GPS walks to place anyone yet.
          </div>
        )}
        {hc && hover && (
          <CanvasTooltip x={hover.x} y={hover.y} boxW={size.w} boxH={size.h}>
            <div className="font-semibold text-white">
              {fmt(hc.users)} {hc.users === 1 ? "person" : "people"}
            </div>
            <div>{fmt(hc.active)} walked in the last 30 days</div>
            <div className="mt-1 text-white/45">
              {(cellCountry && hcIdx >= 0 && cellCountry[hcIdx]) || "—"} · a ~17-mile square around{" "}
              {hc.lat.toFixed(2)}, {hc.lng.toFixed(2)}
            </div>
          </CanvasTooltip>
        )}
      </div>

      <aside className="flex w-full shrink-0 flex-col gap-4 border-t border-white/[0.08] p-4 lg:max-h-[min(560px,70vh)] lg:w-72 lg:overflow-y-auto lg:border-t-0 lg:border-l">
        <div>
          <div className="mad-num text-[30px] leading-none font-extrabold text-white">{fmt(located)}</div>
          <div className="mt-1.5 text-[12.5px] leading-snug text-white/45">
            {metric === "users" ? "people placed on the map" : "placed and walked in the last 30 days"}, of{" "}
            {fmt(s.total_users)}. {fmt(s.unlocated_users)} have never walked with GPS, so they can&apos;t be.
          </div>
        </div>
        <SegmentedControl
          value={metric}
          onChange={setMetric}
          options={[
            { value: "users", label: "Everyone" },
            { value: "active", label: "Active · 30 days" },
          ]}
        />
        <div>
          <div className="mb-2 text-[11px] font-semibold tracking-[0.4px] text-white/45 uppercase">
            Top countries
          </div>
          {byCountry ? (
            <BarList
              color={MAD_RED}
              items={byCountry.slice(0, 10).map(([name, v]) => ({
                label: name,
                value: v.users,
                onClick: () => fitCells(v.cells),
              }))}
              emptyLabel="Nobody to place yet."
            />
          ) : (
            <p className="text-sm text-white/40">Loading…</p>
          )}
        </div>
        {loc.unlocated_by_offset.length > 0 && (
          <div>
            <div className="mb-1 text-[11px] font-semibold tracking-[0.4px] text-white/45 uppercase">
              No GPS walks · by time zone
            </div>
            <p className="mb-2 text-[11px] leading-snug text-white/35">
              The UTC offset their phone last reported — a rough longitude for people the map can&apos;t place.
            </p>
            <BarList
              color="rgba(255,255,255,0.3)"
              items={loc.unlocated_by_offset.slice(0, 6).map((o) => ({
                label: offsetLabel(o.offset_minutes),
                value: o.users,
              }))}
            />
          </div>
        )}
        <p className="text-[11px] leading-snug text-white/30">
          A person is placed in the ~17-mile square their last {loc.routes_per_person} GPS walks mostly run through. This page only ever
          receives squares and counts — never anyone&apos;s coordinates. Stealth-mode walks store no route, so they
          never count.
        </p>
      </aside>
    </div>
  );
}
