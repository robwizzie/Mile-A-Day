"use client";

import { useMemo, useRef, useState } from "react";
import { Download, FileUp, Plus, Trash2 } from "lucide-react";
import { CARD, STACK_SECTIONS } from "../../_components/theme";
import { Card, Section } from "../../_components/lib";
import { SLOTS } from "@/lib/flamey/compose";
import type { MotionSpec, Skin, Slot, Unlock } from "@/lib/flamey/compose";
import type { Recording } from "@/lib/flamey/skinRender";
import { importSvg } from "@/lib/flamey/svgImport";
import {
  LAYER_PARTS,
  MOTION_FIELDS,
  MOTION_KINDS,
  MOTION_PERIOD,
  PIVOTED,
  SLOT_LAYERS,
  skinFileText,
  templateSvg,
  validateSkin,
} from "@/lib/flamey/skinFile";
import type { Problem } from "@/lib/flamey/skinFile";
import { SLOT_LABELS } from "./Gallery";
import { PhoneFits, SurfaceRow } from "./SurfacePreview";
import { MotionToggle, downloadText } from "./SkinDetail";

type Layer = {
  uid: number;
  part: string;
  cond: string;
  file: string;
  rec: Recording | null;
  warnings: string[];
  error?: string;
  bounds: [number, number, number, number] | null;
};
type MotionForm = { kind: MotionSpec["kind"] | ""; period: string; fields: Record<string, string>; pivot: [string, string] };

const INPUT =
  "w-full rounded-lg border border-white/[0.12] bg-black/30 px-3 py-1.5 text-[13px] text-white placeholder-white/30 outline-none focus:border-white/35";
const LABEL = "mb-1 block text-[12px] font-semibold text-white/60";
const BUTTON =
  "inline-flex items-center gap-1.5 rounded-full border border-white/[0.12] px-3 py-1.5 text-xs font-semibold text-white/75 transition hover:border-white/25 hover:text-white disabled:opacity-40";

const DEFAULT_MOTION: Record<string, MotionSpec["kind"]> = {
  "behind:trail": "drift",
  "companion-body": "bob",
  "held-body": "wobble",
  "held-accent": "flutter",
  "bopper-springs": "sway",
};

function FieldErrors({ list }: { list: Problem[] }) {
  if (!list.length) return null;
  return (
    <ul className="mt-1 space-y-0.5">
      {list.map((p, i) => (
        <li key={i} className="text-[11.5px] leading-snug text-[#ffb3c6]">
          {p.msg}
        </li>
      ))}
    </ul>
  );
}
function FieldWarnings({ list }: { list: Problem[] }) {
  if (!list.length) return null;
  return (
    <ul className="mt-1 space-y-0.5">
      {list.map((p, i) => (
        <li key={i} className="text-[11.5px] leading-snug text-[#ffcc80]">
          {p.msg}
        </li>
      ))}
    </ul>
  );
}

const fmt = (n: number) => String(Math.round(n * 1000) / 1000);

export function NewSkin({ existing }: { existing: Skin[] }) {
  const families = useMemo(() => [...new Set(existing.map((s) => s.family))].sort(), [existing]);
  const order = useMemo(() => Math.max(0, ...existing.map((s) => s.order)) + 1, [existing]);

  const [id, setId] = useState("");
  const [name, setName] = useState("");
  const [slot, setSlot] = useState<Slot>("head");
  const [family, setFamily] = useState("");
  const [unlockKind, setUnlockKind] = useState<"always" | "plus" | "badge" | "month">("badge");
  const [unlockValue, setUnlockValue] = useState("");
  const [unlockCopy, setUnlockCopy] = useState("");
  const [holidays, setHolidays] = useState("");
  const [compact, setCompact] = useState(true);
  const [hides, setHides] = useState<string[]>([]);
  const [clashes, setClashes] = useState("");
  const [hoverLift, setHoverLift] = useState("");
  const [headRise, setHeadRise] = useState("");
  const [headScale, setHeadScale] = useState("");
  const [isCape, setIsCape] = useState(false);
  const [floats, setFloats] = useState(false);
  const [hideFace, setHideFace] = useState(false);
  const [hideArms, setHideArms] = useState(false);
  const [drawLast, setDrawLast] = useState(false);
  const [rulesJson, setRulesJson] = useState("");
  const [layers, setLayers] = useState<Layer[]>([]);
  const [motion, setMotion] = useState<Record<string, MotionForm>>({});
  const [still, setStill] = useState(false);
  const nextUid = useRef(1);

  const slotLayers = SLOT_LAYERS[slot] || [];

  function chooseSlot(s: Slot) {
    setSlot(s);
    setCompact(!["held", "companion", "back", "trail", "aura"].includes(s));
    // Re-home layers whose part this slot doesn't draw.
    const parts = SLOT_LAYERS[s] || [];
    setLayers((ls) => ls.map((l) => (parts.length && !parts.includes(l.part) ? { ...l, part: parts[0] } : l)));
  }

  function ensureMotion(base: string, bounds: Layer["bounds"]) {
    setMotion((m) => {
      if (m[base]) return m;
      const kind = DEFAULT_MOTION[base] ?? (base === "behind" && slot === "trail" ? DEFAULT_MOTION["behind:trail"] : undefined);
      const cx = bounds ? (bounds[0] + bounds[2]) / 2 : 0;
      const cy = bounds ? (base === "held-body" ? bounds[3] : (bounds[1] + bounds[3]) / 2) : 0;
      const f: MotionForm = { kind: kind ?? "", period: kind ? String(MOTION_PERIOD[kind]) : "1.6", fields: {}, pivot: [fmt(cx), fmt(cy)] };
      if (kind) for (const x of MOTION_FIELDS[kind]) f.fields[x.key] = String(x.def);
      return { ...m, [base]: f };
    });
  }

  function addLayer() {
    const used = new Set(layers.map((l) => l.part));
    const part = slotLayers.find((p) => !used.has(p)) ?? slotLayers[0] ?? "front";
    setLayers((ls) => [...ls, { uid: nextUid.current++, part, cond: "", file: "", rec: null, warnings: [], bounds: null }]);
  }

  async function upload(uid: number, file: File) {
    const text = await file.text();
    try {
      const r = importSvg(text);
      setLayers((ls) => ls.map((l) => (l.uid === uid ? { ...l, file: file.name, rec: r.recording, warnings: r.warnings, error: undefined, bounds: r.bounds } : l)));
      const layer = layers.find((l) => l.uid === uid);
      if (layer) ensureMotion(layer.part, r.bounds);
    } catch (e) {
      setLayers((ls) => ls.map((l) => (l.uid === uid ? { ...l, file: file.name, rec: null, warnings: [], error: e instanceof Error ? e.message : String(e) } : l)));
    }
  }

  async function downloadTemplate() {
    const blob = await (await fetch("/flamey-skins/plain-card.png")).blob();
    const dataUrl = await new Promise<string>((ok) => {
      const fr = new FileReader();
      fr.onload = () => ok(String(fr.result));
      fr.readAsDataURL(blob);
    });
    downloadText("flamey-skin-template.svg", templateSvg(dataUrl), "image/svg+xml");
  }

  // ---- the skin, as the file will say it
  const { skin, rulesError } = useMemo(() => {
    let rulesError: string | null = null;
    const rules: Skin["rules"] = { hides, clashes: clashes.split(/[\s,]+/).filter(Boolean) };
    const n = (v: string) => (v.trim() === "" ? undefined : Number(v));
    if (slot === "feet" && n(hoverLift) !== undefined) rules.hover_lift = n(hoverLift);
    if ((slot === "head" || slot === "costume") && n(headRise) !== undefined) rules.head_rise = n(headRise);
    if (slot === "head" && n(headScale) !== undefined) rules.head_scale = n(headScale);
    if (slot === "back" && isCape) rules.is_cape = true;
    if (slot === "companion") rules.floats = floats;
    if (slot === "costume" && hideFace) rules.shows_face = false;
    if (slot === "costume" && hideArms) rules.shows_arms = false;
    if (drawLast) rules.draw = "last";
    if (rulesJson.trim()) {
      try {
        const extra = JSON.parse(rulesJson);
        if (!extra || typeof extra !== "object" || Array.isArray(extra)) throw new Error("must be a JSON object");
        Object.assign(rules, extra);
      } catch (e) {
        rulesError = `Advanced rules: ${e instanceof Error ? e.message : String(e)}`;
      }
    }

    let unlock: Unlock = "always";
    if (unlockKind === "always" || unlockKind === "plus") unlock = unlockKind;
    else if (unlockKind === "badge") unlock = { badge: unlockValue.trim() };
    else unlock = { month: Number(unlockValue) };

    const art: Record<string, Recording> = {};
    for (const l of layers) if (l.rec) art[l.part + (l.cond.trim() ? `@${l.cond.trim()}` : "")] = l.rec;
    const bases = new Set(Object.keys(art).map((k) => k.split("@")[0]));

    const motionOut: Record<string, MotionSpec> = {};
    const pivots: Record<string, [number, number]> = {};
    for (const [base, f] of Object.entries(motion)) {
      if (!bases.has(base) || !f.kind) continue;
      const m: MotionSpec = { kind: f.kind, period: Number(f.period) };
      for (const x of MOTION_FIELDS[f.kind]) (m as Record<string, unknown>)[x.key] = Number(f.fields[x.key] ?? x.def);
      // Field order like the shipped files: kind, fields, period.
      const ordered = { kind: m.kind, ...Object.fromEntries(MOTION_FIELDS[f.kind].map((x) => [x.key, m[x.key]])), period: m.period } as MotionSpec;
      motionOut[base] = ordered;
      if (PIVOTED.includes(f.kind)) pivots[base] = [Number(f.pivot[0]), Number(f.pivot[1])];
    }

    const skin: Skin = {
      format: 1,
      id: id.trim(),
      order,
      slot,
      name: name.trim(),
      family: family.trim(),
      unlock,
      unlock_copy: unlockCopy.trim(),
      holidays: holidays.split(/[\s,]+/).filter(Boolean),
      mood_prop: false,
      compact,
      rules,
      art,
    };
    if (Object.keys(pivots).length) skin.pivots = pivots;
    if (Object.keys(motionOut).length) skin.motion = motionOut;
    return { skin, rulesError };
  }, [id, name, slot, family, unlockKind, unlockValue, unlockCopy, holidays, compact, hides, clashes, hoverLift, headRise, headScale, isCape, floats, hideFace, hideArms, drawLast, rulesJson, layers, motion, order]);

  const { errors, warnings } = useMemo(() => {
    const v = validateSkin(skin, existing);
    if (rulesError) v.errors.push({ field: "rules", msg: rulesError });
    for (const l of layers) {
      if (l.error) v.errors.push({ field: "art", msg: `${l.part}: ${l.error}` });
      else if (!l.rec) v.errors.push({ field: "art", msg: `${l.part}: no SVG uploaded yet.` });
    }
    const keys = layers.filter((l) => l.rec).map((l) => l.part + (l.cond.trim() ? `@${l.cond.trim()}` : ""));
    const dup = keys.filter((k, i) => keys.indexOf(k) !== i);
    if (dup.length) v.errors.push({ field: "art", msg: `Two layers are both "${dup[0]}"; give one a different part or conditions.` });
    return v;
  }, [skin, existing, rulesError, layers]);

  const errs = (f: string) => errors.filter((e) => e.field === f);
  const warns = (f: string) => warnings.filter((e) => e.field === f);
  const hasArt = Object.keys(skin.art).length > 0;
  const bases = [...new Set(layers.filter((l) => l.rec).map((l) => l.part))];

  return (
    <div className={STACK_SECTIONS}>
      <Section
        title="New skin"
        hint="Draw on the template, upload the SVG, fill in the details, then download the skin file and add it to backend/flamey-skins/ in a PR."
      >
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
          {/* ---- left: the form */}
          <div className="space-y-5">
            <Card
              title="1. Art"
              hint="Body units: the template's viewBox is -1.5 -1.5 3 3, Flamey's square is the middle third. Its reference and guides layers are skipped on upload."
              actions={
                <button onClick={downloadTemplate} className={BUTTON}>
                  <Download className="h-3.5 w-3.5" /> Download template
                </button>
              }
            >
              <div className="space-y-3">
                {layers.map((l) => (
                  <div key={l.uid} className="rounded-xl border border-white/[0.08] bg-black/20 p-3">
                    <div className="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto] items-end gap-2">
                      <label>
                        <span className={LABEL}>Layer</span>
                        <select
                          className={INPUT}
                          value={l.part}
                          onChange={(e) => {
                            const part = e.target.value;
                            setLayers((ls) => ls.map((x) => (x.uid === l.uid ? { ...x, part } : x)));
                            if (l.rec) ensureMotion(part, l.bounds);
                          }}
                        >
                          {LAYER_PARTS.map((p) => (
                            <option key={p} value={p}>
                              {p}
                              {slotLayers.includes(p) ? "" : " (not drawn for this slot)"}
                            </option>
                          ))}
                        </select>
                      </label>
                      <label>
                        <span className={LABEL}>Conditions (optional)</span>
                        <input
                          className={INPUT}
                          placeholder="e.g. reach=0.62"
                          value={l.cond}
                          onChange={(e) => setLayers((ls) => ls.map((x) => (x.uid === l.uid ? { ...x, cond: e.target.value } : x)))}
                        />
                      </label>
                      <button
                        aria-label="Remove layer"
                        onClick={() => setLayers((ls) => ls.filter((x) => x.uid !== l.uid))}
                        className="mb-0.5 rounded-full p-2 text-white/40 transition hover:bg-white/[0.06] hover:text-white"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                    <div className="mt-2.5 flex flex-wrap items-center gap-3">
                      <label className={`${BUTTON} cursor-pointer`}>
                        <FileUp className="h-3.5 w-3.5" /> {l.file ? "Replace SVG" : "Upload SVG"}
                        <input
                          type="file"
                          accept=".svg,image/svg+xml"
                          className="hidden"
                          data-layer-upload={l.uid}
                          onChange={(e) => {
                            const f = e.target.files?.[0];
                            if (f) upload(l.uid, f);
                            e.target.value = "";
                          }}
                        />
                      </label>
                      {l.file && <span className="truncate font-mono text-[12px] text-white/50">{l.file}</span>}
                      {l.rec && (
                        <span className="text-[12px] text-white/40">
                          {l.rec.ops.length} ops{l.rec.clips?.length ? `, ${l.rec.clips.length} clips` : ""}
                        </span>
                      )}
                    </div>
                    {l.error && <p className="mt-1.5 text-[11.5px] text-[#ffb3c6]">{l.error}</p>}
                    {l.warnings.length > 0 && (
                      <ul className="mt-1.5 space-y-0.5">
                        {l.warnings.map((w) => (
                          <li key={w} className="text-[11.5px] leading-snug text-[#ffcc80]">
                            {w}
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                ))}
                <button onClick={addLayer} className={BUTTON}>
                  <Plus className="h-3.5 w-3.5" /> Add layer
                </button>
                <p className="text-[11.5px] leading-snug text-white/40">
                  {slotLayers.length
                    ? `${SLOT_LABELS[slot]} draws: ${slotLayers.join(", ")}. A layer without conditions is used on every surface.`
                    : "This slot is a built-in effect: no art."}
                </p>
                <FieldErrors list={errs("art")} />
                <FieldWarnings list={warns("art")} />
              </div>
            </Card>

            <Card title="2. Details">
              <div className="grid gap-3 sm:grid-cols-2">
                <label>
                  <span className={LABEL}>Id (permanent)</span>
                  <input className={`${INPUT} font-mono`} placeholder="lightning_cape" value={id} onChange={(e) => setId(e.target.value)} />
                  <FieldErrors list={errs("id")} />
                </label>
                <label>
                  <span className={LABEL}>Name</span>
                  <input className={INPUT} placeholder="Lightning Cape" value={name} onChange={(e) => setName(e.target.value)} />
                  <FieldErrors list={errs("name")} />
                </label>
                <label>
                  <span className={LABEL}>Slot</span>
                  <select className={INPUT} value={slot} onChange={(e) => chooseSlot(e.target.value as Slot)}>
                    {SLOTS.map((s) => (
                      <option key={s} value={s}>
                        {SLOT_LABELS[s]} ({s})
                      </option>
                    ))}
                  </select>
                  <FieldErrors list={errs("slot")} />
                </label>
                <label>
                  <span className={LABEL}>Family (Closet group)</span>
                  <input className={INPUT} list="skin-families" placeholder="holidays" value={family} onChange={(e) => setFamily(e.target.value)} />
                  <datalist id="skin-families">
                    {families.map((f) => (
                      <option key={f} value={f} />
                    ))}
                  </datalist>
                  <FieldErrors list={errs("family")} />
                </label>
                <div>
                  <span className={LABEL}>Unlock</span>
                  <div className="flex gap-2">
                    <select className={`${INPUT} w-28 shrink-0`} value={unlockKind} onChange={(e) => setUnlockKind(e.target.value as typeof unlockKind)}>
                      <option value="always">always</option>
                      <option value="plus">plus</option>
                      <option value="badge">badge</option>
                      <option value="month">month</option>
                    </select>
                    {(unlockKind === "badge" || unlockKind === "month") && (
                      <input
                        className={`${INPUT} font-mono`}
                        placeholder={unlockKind === "badge" ? "badge id" : "1-12"}
                        value={unlockValue}
                        onChange={(e) => setUnlockValue(e.target.value)}
                      />
                    )}
                  </div>
                  <FieldErrors list={errs("unlock")} />
                  <FieldWarnings list={warns("unlock")} />
                </div>
                <label>
                  <span className={LABEL}>Unlock copy</span>
                  <input className={INPUT} placeholder="Walk your mile on ..." value={unlockCopy} onChange={(e) => setUnlockCopy(e.target.value)} />
                  <FieldErrors list={errs("unlock_copy")} />
                </label>
                <label>
                  <span className={LABEL}>Holidays (worn automatically)</span>
                  <input className={`${INPUT} font-mono`} placeholder="halloween" value={holidays} onChange={(e) => setHolidays(e.target.value)} />
                  <FieldErrors list={errs("holidays")} />
                </label>
                <div>
                  <span className={LABEL}>Order</span>
                  <div className="py-1.5 font-mono text-[13px] text-white/70">{order} (last in the Closet)</div>
                  <FieldErrors list={errs("order")} />
                </div>
                <label className="flex items-center gap-2 text-[13px] text-white/75 sm:col-span-2">
                  <input type="checkbox" checked={compact} onChange={(e) => setCompact(e.target.checked)} />
                  Drawn on compact surfaces (widgets, Live Activity)
                </label>
              </div>
            </Card>

            <Card title="3. Rules" hint="How it fits with the rest of him (docs/flamey-skins.md, rules).">
              <div className="space-y-3">
                <div>
                  <span className={LABEL}>Hides these slots</span>
                  <div className="flex flex-wrap gap-x-3 gap-y-1.5">
                    {SLOTS.filter((s) => s !== slot).map((s) => (
                      <label key={s} className="flex items-center gap-1.5 text-[12.5px] text-white/70">
                        <input
                          type="checkbox"
                          checked={hides.includes(s)}
                          onChange={(e) => setHides((h) => (e.target.checked ? [...h, s] : h.filter((x) => x !== s)))}
                        />
                        {s}
                      </label>
                    ))}
                  </div>
                </div>
                <label className="block">
                  <span className={LABEL}>Clashes with (skin ids)</span>
                  <input className={`${INPUT} font-mono`} placeholder="red_cape, blue_cape" value={clashes} onChange={(e) => setClashes(e.target.value)} />
                </label>
                <div className="grid gap-3 sm:grid-cols-3">
                  {slot === "feet" && (
                    <label>
                      <span className={LABEL}>hover_lift</span>
                      <input className={INPUT} inputMode="decimal" placeholder="0.13" value={hoverLift} onChange={(e) => setHoverLift(e.target.value)} />
                    </label>
                  )}
                  {(slot === "head" || slot === "costume") && (
                    <label>
                      <span className={LABEL}>head_rise</span>
                      <input className={INPUT} inputMode="decimal" placeholder="0.25" value={headRise} onChange={(e) => setHeadRise(e.target.value)} />
                    </label>
                  )}
                  {slot === "head" && (
                    <label>
                      <span className={LABEL}>head_scale</span>
                      <input className={INPUT} inputMode="decimal" placeholder="1" value={headScale} onChange={(e) => setHeadScale(e.target.value)} />
                    </label>
                  )}
                </div>
                <div className="flex flex-wrap gap-x-4 gap-y-1.5 text-[12.5px] text-white/70">
                  {slot === "back" && (
                    <label className="flex items-center gap-1.5">
                      <input type="checkbox" checked={isCape} onChange={(e) => setIsCape(e.target.checked)} /> is_cape
                    </label>
                  )}
                  {slot === "companion" && (
                    <label className="flex items-center gap-1.5">
                      <input type="checkbox" checked={floats} onChange={(e) => setFloats(e.target.checked)} /> floats (hovers by his shoulder)
                    </label>
                  )}
                  {slot === "costume" && (
                    <>
                      <label className="flex items-center gap-1.5">
                        <input type="checkbox" checked={hideFace} onChange={(e) => setHideFace(e.target.checked)} /> covers his face
                      </label>
                      <label className="flex items-center gap-1.5">
                        <input type="checkbox" checked={hideArms} onChange={(e) => setHideArms(e.target.checked)} /> covers his arms
                      </label>
                    </>
                  )}
                  <label className="flex items-center gap-1.5">
                    <input type="checkbox" checked={drawLast} onChange={(e) => setDrawLast(e.target.checked)} /> draw last (over chest, eyes and head)
                  </label>
                </div>
                <label className="block">
                  <span className={LABEL}>Advanced rules (JSON, merged in)</span>
                  <textarea
                    className={`${INPUT} h-20 font-mono text-[12px]`}
                    placeholder={slot === "held" ? '{"held": {"hand": [0.4, -0.36], "grip": [0.4, -0.36], "period": 0.55, ...}}' : '{"crown_rise": 0.07}'}
                    value={rulesJson}
                    onChange={(e) => setRulesJson(e.target.value)}
                  />
                </label>
                <FieldErrors list={errs("rules")} />
                <FieldWarnings list={warns("rules")} />
              </div>
            </Card>

            <Card title="4. Motion" hint="One ease-in-out autoreverse per layer. Turning and scaling kinds move about the pivot (body units).">
              {bases.length === 0 && <p className="text-[13px] text-white/45">Upload art first.</p>}
              <div className="space-y-3">
                {bases.map((base) => {
                  const f = motion[base] ?? { kind: "", period: "1.6", fields: {}, pivot: ["0", "0"] as [string, string] };
                  const set = (patch: Partial<MotionForm>) => setMotion((m) => ({ ...m, [base]: { ...f, ...patch } }));
                  return (
                    <div key={base} className="rounded-xl border border-white/[0.08] bg-black/20 p-3">
                      <div className="mb-2 font-mono text-[12px] text-white/60">{base}</div>
                      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                        <label>
                          <span className={LABEL}>Kind</span>
                          <select
                            className={INPUT}
                            value={f.kind}
                            onChange={(e) => {
                              const kind = e.target.value as MotionForm["kind"];
                              const fields: Record<string, string> = {};
                              if (kind) for (const x of MOTION_FIELDS[kind]) fields[x.key] = f.fields[x.key] ?? String(x.def);
                              set({ kind, fields, period: kind ? String(MOTION_PERIOD[kind]) : f.period });
                            }}
                          >
                            <option value="">none (still)</option>
                            {MOTION_KINDS.map((k) => (
                              <option key={k} value={k}>
                                {k}
                              </option>
                            ))}
                          </select>
                        </label>
                        {f.kind && (
                          <label>
                            <span className={LABEL}>Period (s)</span>
                            <input className={INPUT} inputMode="decimal" value={f.period} onChange={(e) => set({ period: e.target.value })} />
                          </label>
                        )}
                        {f.kind &&
                          MOTION_FIELDS[f.kind].map((x) => (
                            <label key={x.key}>
                              <span className={LABEL}>{x.label}</span>
                              <input
                                className={INPUT}
                                inputMode="decimal"
                                value={f.fields[x.key] ?? ""}
                                onChange={(e) => set({ fields: { ...f.fields, [x.key]: e.target.value } })}
                              />
                            </label>
                          ))}
                        {f.kind && PIVOTED.includes(f.kind) && (
                          <>
                            <label>
                              <span className={LABEL}>Pivot x</span>
                              <input className={INPUT} inputMode="decimal" value={f.pivot[0]} onChange={(e) => set({ pivot: [e.target.value, f.pivot[1]] })} />
                            </label>
                            <label>
                              <span className={LABEL}>Pivot y</span>
                              <input className={INPUT} inputMode="decimal" value={f.pivot[1]} onChange={(e) => set({ pivot: [f.pivot[0], e.target.value] })} />
                            </label>
                          </>
                        )}
                      </div>
                    </div>
                  );
                })}
                <FieldErrors list={errs("motion")} />
              </div>
            </Card>
          </div>

          {/* ---- right: live preview */}
          <div className="space-y-5 lg:sticky lg:top-32 lg:self-start">
            <div className={`${CARD} p-5`}>
              <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
                <h2 className="text-[15px] font-bold text-white/90">Preview</h2>
                <MotionToggle still={still} onChange={setStill} />
              </div>
              {hasArt || slot === "aura" || slot === "bubble" ? (
                <SurfaceRow skin={skin} still={still} figure={84} grid="grid-cols-2" />
              ) : (
                <p className="text-[13px] text-white/45">Upload an SVG to see it on Flamey.</p>
              )}
            </div>
            <div className={`${CARD} p-5`}>
              <h2 className="mb-3 text-[15px] font-bold text-white/90">5. Skin file</h2>
              {errors.length ? (
                <>
                  <p className="mb-1.5 text-[12.5px] text-white/55">
                    {errors.length} thing{errors.length === 1 ? "" : "s"} to fix before the file is valid:
                  </p>
                  <ul className="mb-3 list-disc space-y-0.5 pl-5">
                    {errors.slice(0, 8).map((e, i) => (
                      <li key={i} className="text-[12px] text-[#ffb3c6]">
                        {e.msg}
                      </li>
                    ))}
                    {errors.length > 8 && <li className="text-[12px] text-white/40">and {errors.length - 8} more</li>}
                  </ul>
                </>
              ) : (
                <p className="mb-3 text-[12.5px] text-[#7fe39a]">
                  Valid. Save it as backend/flamey-skins/{skin.id}.json, run node backend/scripts/flamey-skins-check.mjs, and open a PR.
                </p>
              )}
              <button
                disabled={errors.length > 0}
                onClick={() => downloadText(`${skin.id}.json`, skinFileText(skin), "application/json")}
                className="inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold text-white shadow-[0_2px_8px_rgba(0,0,0,0.25)] transition disabled:cursor-not-allowed disabled:opacity-40"
                style={{ background: "linear-gradient(135deg, #e64d66 0%, #b3334d 100%)" }}
              >
                <Download className="h-4 w-4" /> Download skin file
              </button>
              {hasArt && (
                <p className="mt-2 text-[11.5px] text-white/35">{(new Blob([skinFileText(skin)]).size / 1024).toFixed(1)} KB</p>
              )}
            </div>
          </div>
        </div>
      </Section>

      {hasArt && (
        <Section title="Fit at phone widths" hint="Approximate layouts at 320, 375 and 440 pt, clipped at each surface's edge.">
          <PhoneFits skin={skin} still={still} />
        </Section>
      )}
    </div>
  );
}
