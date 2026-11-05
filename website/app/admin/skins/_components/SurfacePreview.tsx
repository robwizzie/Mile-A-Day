"use client";

import { CARD } from "../../_components/theme";
import { SURFACES, drawsOn } from "@/lib/flamey/compose";
import type { Skin, Surface } from "@/lib/flamey/compose";
import { FlameyStage } from "./FlameyStage";

export const PHONE_WIDTHS = [320, 375, 440] as const;

/** Aura and bubble skins are built-in effects the app draws from code. */
export const isEffectSkin = (s: Skin) => s.slot === "aura" || s.slot === "bubble";

export function EffectPlaceholder({ skin, size }: { skin: Skin; size: number }) {
  return (
    <div
      className="flex flex-col items-center justify-center gap-1 rounded-xl border border-dashed border-white/20 px-3 text-center"
      style={{ width: size, height: size }}
    >
      <span className="text-[11px] font-bold tracking-wide text-white/60 uppercase">Built-in effect</span>
      <span className="font-mono text-[11px] text-white/45">{(skin.effects || [`${skin.slot}:${skin.id}`]).join(", ")}</span>
      <span className="text-[11px] leading-snug text-white/35">Drawn by app code, not by the skin file</span>
    </div>
  );
}

/**
 * The skin on all four surfaces, each a square of Flamey's stage cropped to
 * +-`span` body units around him.
 */
export function SurfaceRow({
  skin,
  still,
  figure = 120,
  span = 1.05,
  grid = "grid-cols-2 md:grid-cols-4",
}: {
  skin: Skin;
  still: boolean;
  figure?: number;
  span?: number;
  grid?: string;
}) {
  const box = Math.round(figure * span * 2);
  return (
    <div className={`grid gap-3 ${grid}`}>
      {SURFACES.map((s) => (
        <div key={s.name} className={`${CARD} flex flex-col items-center p-3`}>
          <div className="mb-2 flex w-full items-baseline justify-between">
            <span className="text-[13px] font-bold text-white/85">{s.label}</span>
            <span className="text-[11px] text-white/40">{s.compact ? "compact" : `reach ${s.reach}`}</span>
          </div>
          {isEffectSkin(skin) ? (
            <EffectPlaceholder skin={skin} size={box} />
          ) : (
            <div className="relative overflow-hidden rounded-lg bg-black/40" style={{ width: box, height: box }}>
              {/* Crop centred a little above his middle (hats rise; nothing hangs below the floor). */}
              <div className="absolute" style={{ left: box / 2 - figure * 1.5, top: box / 2 - figure * 1.35 }}>
                <FlameyStage skin={skin} surface={s} size={figure * 3} still={still} />
              </div>
              {!drawsOn(skin, s) && (
                <span className="absolute inset-x-0 bottom-1.5 text-center text-[11px] text-white/45">Not drawn on compact surfaces</span>
              )}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

// ---- approximate surface layouts at a phone width (points)

type Layout = { w: number; h: number; figure: number; cx: number; cy: number; radius: number; stats?: boolean };

/**
 * Rough stand-ins for where each surface puts Flamey on a phone `pw` points
 * wide: a full-width card, a half-width tile, the dashboard hero (Flamey in a
 * left column beside the stat column: the tight surface), a small widget.
 * They exist to show FIT (what crosses an edge), not pixel-exact layouts.
 */
function layout(s: Surface, pw: number): Layout {
  switch (s.name) {
    case "card": {
      const w = pw - 32;
      const figure = Math.round(pw * 0.34);
      const h = Math.round(figure * 1.55);
      return { w, h, figure, cx: w / 2, cy: h - figure * 0.62, radius: 16 };
    }
    case "tile": {
      const w = Math.round((pw - 32 - 12) / 2);
      const figure = Math.round(w * 0.58);
      const h = Math.round(w * 1.05);
      return { w, h, figure, cx: w / 2, cy: h - figure * 0.62, radius: 16 };
    }
    case "hero": {
      const w = pw - 32;
      const figure = Math.round(pw * 0.38);
      const h = Math.round(figure * 1.5);
      return { w, h, figure, cx: 12 + figure * 0.53, cy: h - figure * 0.6, radius: 16, stats: true };
    }
    case "widget": {
      const w = Math.round(pw * 0.37 + 22);
      const figure = Math.round(w * 0.62);
      return { w, h: w, figure, cx: w / 2, cy: w - figure * 0.55, radius: 22 };
    }
  }
}

function PhoneSurface({ skin, surface, pw, scale, still }: { skin: Skin; surface: Surface; pw: number; scale: number; still: boolean }) {
  const L = layout(surface, pw);
  const k = scale;
  return (
    <div
      className="relative overflow-hidden border border-white/[0.08] bg-white/[0.05]"
      style={{ width: L.w * k, height: L.h * k, borderRadius: L.radius * k }}
    >
      {L.stats && (
        <div className="absolute flex flex-col gap-1.5" style={{ left: (L.cx + L.figure * 0.5 + 6) * k, top: L.h * 0.22 * k, right: 10 * k }}>
          <div className="h-2.5 w-3/4 rounded-full bg-white/[0.16]" />
          <div className="h-5 w-1/2 rounded-md bg-white/[0.10]" />
          <div className="h-2 w-2/3 rounded-full bg-white/[0.10]" />
          <div className="h-2 w-1/2 rounded-full bg-white/[0.08]" />
        </div>
      )}
      {isEffectSkin(skin) ? null : (
        <div className="absolute" style={{ left: (L.cx - L.figure * 1.5) * k, top: (L.cy - L.figure * 1.5) * k }}>
          <FlameyStage skin={skin} surface={surface} size={L.figure * 3 * k} still={still} />
        </div>
      )}
    </div>
  );
}

/** Every surface at 320, 375 and 440 pt, drawn at `scale` px per pt. */
export function PhoneFits({ skin, still, scale = 0.62 }: { skin: Skin; still: boolean; scale?: number }) {
  if (isEffectSkin(skin)) return <p className="text-sm text-white/40">Built-in effects have no art to fit.</p>;
  return (
    <div className="space-y-5 overflow-x-auto">
      {SURFACES.map((s) => (
        <div key={s.name}>
          <div className="mb-2 text-[12px] font-bold text-white/70">{s.label}</div>
          <div className="flex items-end gap-5">
            {PHONE_WIDTHS.map((pw) => (
              <div key={pw} className="shrink-0">
                <PhoneSurface skin={skin} surface={s} pw={pw} scale={scale} still={still} />
                <div className="mt-1 text-[11px] text-white/40">{pw} pt</div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
