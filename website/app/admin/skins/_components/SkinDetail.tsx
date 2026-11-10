"use client";

import { useState } from "react";
import { ChevronLeft, Download } from "lucide-react";
import { STACK_SECTIONS } from "../../_components/theme";
import { Card, Chip, Section, SegmentedControl } from "../../_components/lib";
import type { Skin } from "@/lib/flamey/compose";
import { skinFileText, stringifySkin } from "@/lib/flamey/skinFile";
import { PaletteSwatches, SLOT_LABELS, unlockText } from "./Gallery";
import { PhoneFits, SurfaceRow } from "./SurfacePreview";
import { go } from "./SkinBuilder";

export function downloadText(name: string, text: string, type: string) {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function MotionToggle({ still, onChange }: { still: boolean; onChange: (v: boolean) => void }) {
  return (
    <SegmentedControl
      value={still ? "still" : "animate"}
      options={[
        { value: "animate", label: "Animate" },
        { value: "still", label: "Still" },
      ]}
      onChange={(v) => onChange(v === "still")}
    />
  );
}

function Row({ k, children }: { k: string; children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-[120px_minmax(0,1fr)] gap-3 border-b border-white/[0.05] py-2 text-[13px] last:border-0">
      <span className="text-white/45">{k}</span>
      <span className="min-w-0 break-words text-white/85">{children}</span>
    </div>
  );
}

// The file's own layout: short objects stay on one line.
const Json = ({ v }: { v: unknown }) => (
  <pre className="overflow-x-auto rounded-lg bg-black/40 p-3 font-mono text-[11.5px] leading-relaxed text-white/75">{stringifySkin(v)}</pre>
);

export function SkinFacts({ skin }: { skin: Skin }) {
  const layers = Object.entries(skin.art || {});
  return (
    <div className="grid gap-5 lg:grid-cols-2">
      <Card title="Unlock">
        <Row k="Unlock">{unlockText(skin.unlock)}</Row>
        <Row k="Closet copy">{skin.unlock_copy || "-"}</Row>
        <Row k="Family">{skin.family}</Row>
        <Row k="Order">{skin.order}</Row>
        <Row k="Holidays">{skin.holidays?.length ? skin.holidays.join(", ") : "-"}</Row>
        <Row k="Compact">{skin.compact ? "Drawn on widgets" : "Full surfaces only"}</Row>
        <Row k="Mood prop">{skin.mood_prop ? "Yes (never in the Closet)" : "No"}</Row>
        {skin.effects?.length ? <Row k="Effects">{skin.effects.join(", ")}</Row> : null}
      </Card>
      <Card title="Rules">
        <Json v={skin.rules} />
      </Card>
      <Card title="Motion">
        {skin.motion && Object.keys(skin.motion).length ? (
          <>
            {Object.entries(skin.motion).map(([base, m]) => (
              <Row key={base} k={base}>
                <span className="font-semibold">{m.kind}</span>{" "}
                <span className="font-mono text-[12px] text-white/55">
                  {Object.entries(m)
                    .filter(([k]) => k !== "kind")
                    .map(([k, v]) => `${k} ${v}`)
                    .join(" · ")}
                </span>
              </Row>
            ))}
            {skin.pivots && (
              <Row k="Pivots">
                {Object.entries(skin.pivots).map(([k, p]) => (
                  <div key={k} className="font-mono text-[12px] text-white/55">
                    {k} <span className="text-white/80">[{p.join(", ")}]</span>
                  </div>
                ))}
              </Row>
            )}
          </>
        ) : (
          <p className="text-[13px] text-white/45">Still: no motion.</p>
        )}
      </Card>
      <Card title={`Layers (${layers.length})`}>
        {layers.length ? (
          layers.map(([k, rec]) => (
            <Row key={k} k={k.split("@")[0]}>
              <span className="font-mono text-[12px] text-white/55">{k.includes("@") ? k.split("@")[1] : "any surface"}</span>
              <span className="ml-2 text-white/40">
                {rec.ops.length} ops{rec.clips?.length ? `, ${rec.clips.length} clips` : ""}
              </span>
            </Row>
          ))
        ) : (
          <p className="text-[13px] text-white/45">No art of its own.</p>
        )}
      </Card>
      {skin.palette && (
        <Card title="Palette" className="lg:col-span-2" hint="Color skins recolor Flamey's body; the app draws him from these.">
          <PaletteSwatches palette={skin.palette} size={20} />
          <div className="mt-4">
            <Json v={skin.palette} />
          </div>
        </Card>
      )}
    </div>
  );
}

export function SkinDetail({ skin }: { skin: Skin }) {
  const [still, setStill] = useState(false);
  return (
    <div className={STACK_SECTIONS}>
      <div>
        <button onClick={() => go("")} className="mb-4 flex items-center gap-1 text-sm text-white/50 transition hover:text-white">
          <ChevronLeft className="h-4 w-4" /> All skins
        </button>
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div className="min-w-0">
            <h2 className="text-[26px] leading-tight font-extrabold">{skin.name}</h2>
            <div className="mt-1.5 flex flex-wrap items-center gap-2">
              <span className="font-mono text-[12px] text-white/45">{skin.id}</span>
              <Chip text={SLOT_LABELS[skin.slot] ?? skin.slot} tone="info" />
              <Chip text={unlockText(skin.unlock)} />
              <Chip text={`format ${skin.format}`} />
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <MotionToggle still={still} onChange={setStill} />
            <button
              onClick={() => downloadText(`${skin.id}.json`, skinFileText(skin), "application/json")}
              className="flex items-center gap-1.5 rounded-full border border-white/[0.12] px-3 py-1 text-xs font-semibold text-white/70 transition hover:border-white/25 hover:text-white"
            >
              <Download className="h-3.5 w-3.5" /> Skin file
            </button>
          </div>
        </div>
      </div>

      <Section title="Surfaces" hint="Worn alone on each surface, composed the way the app does: behind layers, Flamey, front layers.">
        {skin.slot === "color" && (
          <p className="-mt-1 text-[12.5px] text-white/45">
            The app draws a color from code, so these previews draw his body the same way, in this palette.
          </p>
        )}
        <SurfaceRow skin={skin} still={still} />
      </Section>

      <Section title="Fit at phone widths" hint="Approximate layouts at 320, 375 and 440 pt, clipped at each surface's edge.">
        <PhoneFits skin={skin} still={still} />
      </Section>

      <Section title="Details">
        <SkinFacts skin={skin} />
      </Section>
    </div>
  );
}
