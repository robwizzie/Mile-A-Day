"use client";

import { useEffect, useRef } from "react";
import { CONSTANTS, composeLook, loadSkinImages, paletteTokens } from "@/lib/flamey/compose";
import { drawFlameyBody, type PaletteJson } from "@/lib/flamey/flameyBody";
import type { Skin, Surface, SurfaceName } from "@/lib/flamey/compose";
import type { ImageMap } from "@/lib/flamey/skinRender";

// ---- one clock for every animated canvas on the page

type Tick = (t: number) => void;
const ticks = new Set<Tick>();
let raf = 0;
function loop() {
  const t = performance.now() / 1000;
  for (const f of ticks) f(t);
  raf = ticks.size ? requestAnimationFrame(loop) : 0;
}
function subscribe(f: Tick) {
  ticks.add(f);
  if (!raf) raf = requestAnimationFrame(loop);
  return () => {
    ticks.delete(f);
  };
}

// ---- assets

const plainCache = new Map<SurfaceName, Promise<HTMLImageElement>>();
export function plainImage(s: SurfaceName): Promise<HTMLImageElement> {
  let p = plainCache.get(s);
  if (!p) {
    p = new Promise((ok, no) => {
      const img = new Image();
      img.onload = () => ok(img);
      img.onerror = no;
      img.src = `/flamey-skins/plain-${s}.png`;
    });
    plainCache.set(s, p);
  }
  return p;
}

const imageCache = new WeakMap<Skin, Promise<ImageMap>>();
function skinImages(skin: Skin): Promise<ImageMap> {
  let p = imageCache.get(skin);
  if (!p) {
    p = loadSkinImages(skin);
    imageCache.set(skin, p);
  }
  return p;
}

/**
 * One look on one surface: a canvas of the 3-unit stage (Flamey's square is
 * its middle third), `size` CSS px wide. Animated through the shared clock
 * unless `still` or the skin has no motion.
 */
export function FlameyStage({
  skin,
  surface,
  size,
  still = false,
  className = "",
}: {
  skin: Skin;
  surface: Surface;
  size: number;
  still?: boolean;
  className?: string;
}) {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const cv = ref.current;
    if (!cv) return;
    let alive = true;
    let unsub: (() => void) | null = null;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const W = Math.round(size * dpr);
    cv.width = W;
    cv.height = W;
    const ctx = cv.getContext("2d");
    if (!ctx) return;
    // A color skin's own palette feeds `tok` paints (its crown), and
    // recolors his body: the app draws a color from code, not from layers,
    // so the plain image (default colors) would hide the very thing the skin
    // is. flameyBody.ts draws him from the same shapes in the skin's palette.
    const isColor = skin.slot === "color" && !!skin.palette;
    const palette = isColor ? paletteTokens(skin.palette) : null;
    const drawBody = () => {
      const U = W / 3;
      ctx.save();
      ctx.translate(W / 2, W / 2);
      ctx.scale(U, U);
      if (surface.compact) {
        // The widget figure, as compose.ts places layers on it.
        ctx.translate(0, 0.5);
        ctx.scale(1 / (1 + CONSTANTS.leg_length), 1 / (1 + CONSTANTS.leg_length));
        ctx.translate(0, -0.5);
      }
      drawFlameyBody(ctx, { palette: skin.palette as PaletteJson });
      ctx.restore();
    };

    Promise.all([plainImage(surface.name), skinImages(skin)]).then(([plain, images]) => {
      if (!alive) return;
      const draw = (time: number | null) => {
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, W, W);
        if (isColor) {
          // A color skin's only art is a crown in front, so the body goes first.
          drawBody();
          composeLook(ctx, W, skin, surface, { images }, { time, palette, shadowScale: 2, figure: false });
        } else {
          composeLook(ctx, W, skin, surface, { plain, images }, { time, palette, shadowScale: 2 });
        }
      };
      const animated = !still && skin.motion && Object.keys(skin.motion).length > 0;
      if (animated) unsub = subscribe((t) => draw(t));
      else draw(null);
    });
    return () => {
      alive = false;
      unsub?.();
    };
  }, [skin, surface, size, still]);

  return <canvas ref={ref} className={className} style={{ width: size, height: size, display: "block" }} />;
}
