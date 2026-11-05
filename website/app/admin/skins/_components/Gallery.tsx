"use client";

import { useMemo, useState } from "react";
import { Search } from "lucide-react";
import { CARD_INTERACTIVE, STACK_SECTIONS } from "../../_components/theme";
import { Section } from "../../_components/lib";
import { SLOTS, SURFACES } from "@/lib/flamey/compose";
import type { Skin } from "@/lib/flamey/compose";
import { FlameyStage } from "./FlameyStage";
import { EffectPlaceholder, isEffectSkin } from "./SurfacePreview";
import { go } from "./SkinBuilder";

export const SLOT_LABELS: Record<string, string> = {
  color: "Colours",
  head: "Head",
  eyes: "Eyes",
  chest: "Chest",
  back: "Back",
  feet: "Feet",
  costume: "Costumes",
  held: "Held",
  trail: "Trails",
  companion: "Companions",
  aura: "Auras",
  bubble: "Speech bubbles",
};

export function unlockText(u: Skin["unlock"]): string {
  if (u === "always") return "Always";
  if (u === "plus") return "Plus";
  if ("badge" in u) return `Badge ${u.badge}`;
  return `Month ${u.month}`;
}

/** A colour skin's palette as swatches (the body itself is drawn by app code). */
export function PaletteSwatches({ palette, size = 14 }: { palette?: Record<string, unknown>; size?: number }) {
  if (!palette) return null;
  const rows: [string, string[]][] = [];
  for (const k of ["outer", "inner", "core", "glow", "rim", "eye"]) {
    const v = palette[k];
    const list = Array.isArray(v) ? v : typeof v === "string" ? [v] : [];
    const colours = list.filter((c): c is string => typeof c === "string" && c.startsWith("#"));
    if (colours.length) rows.push([k, colours]);
  }
  return (
    <div className="flex flex-wrap gap-x-2.5 gap-y-1">
      {rows.map(([k, cs]) => (
        <span key={k} className="flex items-center gap-1" title={k}>
          <span className="flex">
            {cs.map((c, i) => (
              <span
                key={i}
                className="border border-black/40 first:rounded-l-[4px] last:rounded-r-[4px]"
                style={{ width: size, height: size, background: c }}
              />
            ))}
          </span>
          <span className="text-[10px] text-white/40">{k}</span>
        </span>
      ))}
    </div>
  );
}

const CARD_SURFACE = SURFACES[0];

function Tile({ skin }: { skin: Skin }) {
  const figure = 80;
  const box = 160;
  // Crop centred a little above his middle: hats rise, nothing hangs below the floor.
  const cy = -0.15;
  const isColour = skin.slot === "color";
  return (
    <button onClick={() => go(`skin/${skin.id}`)} className={`${CARD_INTERACTIVE} flex flex-col items-center p-3 text-left`}>
      {isEffectSkin(skin) ? (
        <EffectPlaceholder skin={skin} size={box} />
      ) : (
        <div className="relative overflow-hidden" style={{ width: box, height: box }}>
          <div className="absolute" style={{ left: box / 2 - figure * 1.5, top: box / 2 - figure * (1.5 + cy) }}>
            <FlameyStage skin={skin} surface={CARD_SURFACE} size={figure * 3} still />
          </div>
        </div>
      )}
      <div className="mt-2 w-full min-w-0">
        <div className="truncate text-[13px] font-bold text-white/90">{skin.name}</div>
        <div className="truncate font-mono text-[11px] text-white/40">{skin.id}</div>
        {isColour && (
          <div className="mt-1.5">
            <PaletteSwatches palette={skin.palette} size={10} />
          </div>
        )}
      </div>
    </button>
  );
}

export function Gallery({ skins }: { skins: Skin[] }) {
  const [q, setQ] = useState("");
  const groups = useMemo(() => {
    const needle = q.trim().toLowerCase();
    const hit = (s: Skin) =>
      !needle ||
      [s.id, s.name, s.family, s.slot, s.unlock_copy, unlockText(s.unlock)].some((v) => String(v).toLowerCase().includes(needle));
    return SLOTS.map((slot) => ({
      slot,
      skins: skins.filter((s) => s.slot === slot && hit(s)).sort((a, b) => a.order - b.order),
    })).filter((g) => g.skins.length);
  }, [skins, q]);

  return (
    <div className={STACK_SECTIONS}>
      <div className="relative max-w-md">
        <Search className="pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-white/35" />
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search by name, id, family or unlock"
          className="w-full rounded-full border border-white/[0.12] bg-white/[0.05] py-2 pr-4 pl-9 text-sm text-white placeholder-white/35 outline-none focus:border-white/30"
        />
      </div>
      {!groups.length && <p className="text-sm text-white/45">No skins match &quot;{q}&quot;.</p>}
      {groups.map((g) => (
        <Section
          key={g.slot}
          title={`${SLOT_LABELS[g.slot]} (${g.skins.length})`}
          hint={
            g.slot === "color"
              ? "A colour recolours Flamey's body, which the app draws itself: shown here as its palette, plus its crown layer if it has one."
              : g.slot === "aura" || g.slot === "bubble"
                ? "Built-in effects drawn by app code; the skin file only names them."
                : undefined
          }
        >
          <div className="grid grid-cols-[repeat(auto-fill,minmax(184px,1fr))] gap-3">
            {g.skins.map((s) => (
              <Tile key={s.id} skin={s} />
            ))}
          </div>
        </Section>
      ))}
    </div>
  );
}
