// The skin file itself: the exact JSON layout the repo's files use
// (app/FlameyExport/convert/assemble.mjs `stringify`), the doc's validation
// rules (backend/scripts/flamey-skins-check.mjs + docs/flamey-skins.md), and
// the drawing template.

import { ANCHORS, SLOTS, parseLayerKey } from "./compose";
import type { MotionSpec, Skin } from "./compose";
import type { Recording } from "./skinRender";

// ---------------------------------------------------------------- layout

/**
 * Pretty at the top, one op per line inside recordings: the same text
 * assemble.mjs writes, so a new file diffs like the migrated ones. Ops and
 * clips keep sorted keys like the exporter's.
 */
export function stringifySkin(v: unknown, indent = ""): string {
  const next = indent + "  ";
  if (Array.isArray(v)) {
    if (v.every((x) => x === null || typeof x !== "object")) return JSON.stringify(v);
    if (v.every((x) => x && typeof x === "object" && !Array.isArray(x) && ("op" in x || "d" in x))) {
      return "[\n" + v.map((x) => next + JSON.stringify(sortKeys(x))).join(",\n") + "\n" + indent + "]";
    }
    return "[\n" + v.map((x) => next + stringifySkin(x, next)).join(",\n") + "\n" + indent + "]";
  }
  if (v && typeof v === "object") {
    const o = v as Record<string, unknown>;
    const keys = Object.keys(o);
    if (!keys.length) return "{}";
    if (
      keys.every((k) => o[k] === null || typeof o[k] !== "object" || (Array.isArray(o[k]) && (o[k] as unknown[]).every((x) => typeof x !== "object"))) &&
      JSON.stringify(v).length < 100
    ) return JSON.stringify(v);
    return "{\n" + keys.map((k) => next + JSON.stringify(k) + ": " + stringifySkin(o[k], next)).join(",\n") + "\n" + indent + "}";
  }
  return JSON.stringify(v);
}

function sortKeys(x: unknown): unknown {
  if (Array.isArray(x)) return x.map(sortKeys);
  if (x && typeof x === "object") {
    const o = x as Record<string, unknown>;
    return Object.fromEntries(Object.keys(o).sort().map((k) => [k, sortKeys(o[k])]));
  }
  return x;
}

function sortTop<T extends object>(o: T): T {
  return Object.fromEntries(Object.keys(o).sort().map((k) => [k, (o as Record<string, unknown>)[k]])) as T;
}

/** Field order of the repo's files. */
export function orderedSkin(s: Skin): Skin {
  const out: Record<string, unknown> = {
    format: s.format,
    id: s.id,
    order: s.order,
    slot: s.slot,
    name: s.name,
    family: s.family,
    unlock: s.unlock,
    unlock_copy: s.unlock_copy,
    holidays: s.holidays,
    mood_prop: s.mood_prop,
    compact: s.compact,
    rules: s.rules,
  };
  if (s.palette) out.palette = s.palette;
  if (s.effects?.length) out.effects = s.effects;
  // Recordings keep sorted keys (clips, images, ops) like the exporter's.
  out.art = Object.fromEntries(Object.entries(s.art || {}).map(([k, rec]) => [k, sortTop(rec)]));
  if (s.pivots && Object.keys(s.pivots).length) out.pivots = s.pivots;
  if (s.motion && Object.keys(s.motion).length) out.motion = s.motion;
  return out as Skin;
}

export const skinFileText = (s: Skin) => stringifySkin(orderedSkin(s)) + "\n";

// ---------------------------------------------------------------- vocab

export const LAYER_PARTS = [
  "front", "behind", "crown", "held-body", "held-accent", "companion-body", "companion-shadow", "bopper-band", "bopper-springs",
] as const;

/** Which layers make sense for a slot (the Closet's renderer draws them there). */
export const SLOT_LAYERS: Record<string, string[]> = {
  color: ["crown"],
  head: ["front", "bopper-band", "bopper-springs"],
  eyes: ["front"],
  chest: ["front"],
  costume: ["front"],
  feet: ["front"],
  back: ["behind"],
  trail: ["behind"],
  held: ["held-body", "held-accent"],
  companion: ["companion-body", "companion-shadow"],
  aura: [],
  bubble: [],
};

export const CONDITIONS: Record<string, string[]> = {
  reach: ["0.9", "0.8", "0.62"],
  low: ["0", "1"],
  jets: ["0", "1"],
  glow: ["0", "1"],
  pose: ["rest", "cheer", "highFive", "cheeks", "tucked", "feedOut", "feed", "flail"],
};

export const MOTION_KINDS: MotionSpec["kind"][] = ["drift", "bob", "sway", "wobble", "pump", "flutter", "sweep", "pulse", "burst"];

/** The fields each motion kind reads (period is always there), with defaults. */
export const MOTION_FIELDS: Record<MotionSpec["kind"], { key: keyof MotionSpec; label: string; def: number }[]> = {
  drift: [
    { key: "dx", label: "dx", def: -0.035 },
    { key: "dx_tight", label: "dx tight", def: -0.015 },
    { key: "alpha", label: "alpha", def: 0.78 },
  ],
  bob: [{ key: "dy", label: "dy", def: -0.02 }],
  sway: [{ key: "deg", label: "degrees", def: 6 }],
  wobble: [
    { key: "deg", label: "degrees", def: 9 },
    { key: "back", label: "back", def: 0.35 },
  ],
  pump: [
    { key: "scale", label: "scale", def: 1.07 },
    { key: "dy", label: "dy", def: -0.012 },
  ],
  flutter: [],
  sweep: [],
  pulse: [],
  burst: [],
};
export const MOTION_PERIOD: Record<MotionSpec["kind"], number> = {
  drift: 1.6, bob: 1.6, sway: 1.6, wobble: 0.55, pump: 0.22, flutter: 0.55, sweep: 0.55, pulse: 0.55, burst: 0.55,
};
/** Kinds that turn or scale about `pivots[layer]`. */
export const PIVOTED: MotionSpec["kind"][] = ["sway", "wobble", "pump", "flutter", "sweep", "pulse", "burst"];

// ---------------------------------------------------------------- validation

export type Problem = { field: string; msg: string };

const HEX = /^#[0-9A-Fa-f]{8}$/;
const NUM = "-?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?";
const PATH_RE = new RegExp(`^(?:\\s*(?:[MLQCZ]|${NUM})(?:\\s*,)?)*\\s*$`);
const isNum = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const isNumArr = (v: unknown, n?: number) => Array.isArray(v) && (n === undefined || v.length === n) && v.every(isNum);

function pathError(d: unknown): string | null {
  if (typeof d !== "string" || !d.length) return "d missing";
  if (!PATH_RE.test(d)) return "d has commands outside M L Q C Z";
  if (!/^\s*M/.test(d)) return "d must start with M";
  return null;
}
function colorError(c: unknown): string | null {
  if (typeof c === "string") return HEX.test(c) ? null : `colour ${JSON.stringify(c)} not #RRGGBBAA`;
  if (c && typeof c === "object" && !Array.isArray(c) && "tok" in c) {
    const t = c as Record<string, unknown>;
    if (typeof t.tok !== "string" || !t.tok) return "token without tok";
    if ("a" in t && !isNum(t.a)) return "token a not a number";
    if ("fb" in t && !(typeof t.fb === "string" && HEX.test(t.fb))) return "token fb not #RRGGBBAA";
    return null;
  }
  return "bad colour";
}
function paintError(p: unknown): string | null {
  if (p === undefined) return "paint missing";
  if (typeof p === "string" || (p && typeof p === "object" && "tok" in p)) return colorError(p);
  if (!p || typeof p !== "object" || Array.isArray(p)) return "bad paint";
  const o = p as Record<string, unknown>;
  const kind = (["lin", "rad", "conic"] as const).filter((k) => k in o);
  if (kind.length !== 1) return "paint is not a colour, token or one gradient";
  const n = { lin: 4, rad: 4, conic: 3 }[kind[0]];
  if (!isNumArr(o[kind[0]], n)) return `${kind[0]} needs ${n} numbers`;
  if (!Array.isArray(o.stops) || o.stops.length < 1) return `${kind[0]} gradient without stops`;
  for (const s of o.stops) {
    if (!Array.isArray(s) || s.length !== 2 || !isNum(s[0])) return "stop must be [t, colour]";
    const e = colorError(s[1]);
    if (e) return `stop ${e}`;
  }
  return null;
}
export function recordingErrors(rec: Recording): string[] {
  const out: string[] = [];
  if (!rec || typeof rec !== "object" || !Array.isArray(rec.ops)) return ["recording without ops[]"];
  if (!rec.ops.length) out.push("no ops (nothing to draw)");
  const clips = rec.clips ?? [];
  clips.forEach((c, i) => {
    const e = pathError(c?.d);
    if (e) out.push(`clips[${i}] ${e}`);
  });
  const images = rec.images ?? {};
  for (const [k, v] of Object.entries(images)) if (typeof v !== "string" || !v.startsWith("data:image/")) out.push(`images.${k} not a data:image URL`);
  rec.ops.forEach((o, i) => {
    const at = `ops[${i}]`;
    const op = o as unknown as Record<string, unknown>;
    if (!["fill", "stroke", "image"].includes(String(op.op))) return out.push(`${at} op ${JSON.stringify(op.op)}`);
    if (op.op === "image") {
      if (typeof op.src !== "string" || !(op.src in images)) out.push(`${at} image src not in images`);
      if (!isNumArr(op.rect, 4)) out.push(`${at} image rect needs 4 numbers`);
    } else {
      const pe = pathError(op.d);
      if (pe) out.push(`${at} ${pe}`);
      const pa = paintError(op.paint);
      if (pa) out.push(`${at} ${pa}`);
      if (op.op === "stroke" && !isNum(op.w)) out.push(`${at} stroke without w`);
    }
    if ("m" in op && !isNumArr(op.m, 6)) out.push(`${at} m needs 6 numbers`);
    if ("a" in op && !isNum(op.a)) out.push(`${at} a not a number`);
    if ("clip" in op && !(Array.isArray(op.clip) && op.clip.every((c) => Number.isInteger(c) && c >= 0 && c < clips.length))) {
      out.push(`${at} clip out of range`);
    }
  });
  return out;
}

export const FILE_MAX = 400 * 1024;

/**
 * Everything flamey-skins-check.mjs fails on that can be known here, plus the
 * doc's rules for layers, motion and pivots. `existing` = the skins already
 * in the repo (ids and orders must not collide). Warnings don't block.
 */
export function validateSkin(s: Skin, existing: Skin[]): { errors: Problem[]; warnings: Problem[] } {
  const errors: Problem[] = [];
  const warnings: Problem[] = [];
  const err = (field: string, msg: string) => errors.push({ field, msg });
  const warn = (field: string, msg: string) => warnings.push({ field, msg });

  if (!/^[a-z][a-z0-9_]*$/.test(s.id || "")) err("id", "Lowercase snake_case: letters, digits and _ , starting with a letter.");
  else if (existing.some((e) => e.id === s.id)) err("id", `"${s.id}" is already a skin. Ids are permanent: pick a new one.`);
  if (!s.name?.trim()) err("name", "Name it.");
  if (!(SLOTS as readonly string[]).includes(s.slot)) err("slot", "Pick a slot.");
  if (!s.family?.trim()) err("family", "Family (the Closet group) is required.");
  if (!s.unlock_copy?.trim()) err("unlock_copy", "Say how it's unlocked (shown in the Closet).");
  if (!Number.isInteger(s.order)) err("order", "Order must be an integer.");
  else if (existing.some((e) => e.order === s.order)) err("order", `Order ${s.order} is taken.`);

  const u = s.unlock;
  if (u === "always" || u === "plus") {
    // ok
  } else if (u && typeof u === "object" && "badge" in u) {
    if (!/^[a-z0-9_]+$/.test(u.badge || "")) err("unlock", "Badge id: lowercase letters, digits and _.");
    else if (!existing.some((e) => typeof e.unlock === "object" && "badge" in e.unlock && e.unlock.badge === u.badge)) {
      warn("unlock", `No existing skin unlocks with "${u.badge}". It must be a seeded badge or the CI check fails.`);
    }
  } else if (u && typeof u === "object" && "month" in u) {
    if (!Number.isInteger(u.month) || u.month < 1 || u.month > 12) err("unlock", "Month must be 1 to 12.");
  } else err("unlock", "Unlock is always, plus, a badge or a month.");

  if (!Array.isArray(s.holidays) || !s.holidays.every((h) => typeof h === "string")) err("holidays", "Holidays must be a list of HolidayKey values.");

  // Rules.
  const r = s.rules || {};
  for (const h of r.hides || []) if (!(SLOTS as readonly string[]).includes(h)) err("rules", `hides: "${h}" isn't a slot.`);
  for (const c of r.clashes || []) if (!existing.some((e) => e.id === c)) warn("rules", `clashes: no skin "${c}".`);
  if (r.hover_lift !== undefined) {
    if (!isNum(r.hover_lift) || r.hover_lift < 0 || r.hover_lift > 0.5) err("rules", "hover_lift is 0 to 0.5 body units.");
    if (s.slot !== "feet") warn("rules", "hover_lift only applies to feet.");
  }
  for (const k of ["head_rise", "head_scale"] as const) {
    if (r[k] !== undefined && !isNum(r[k])) err("rules", `${k} must be a number.`);
  }
  if (r.head_rise !== undefined && !["head", "costume"].includes(s.slot)) warn("rules", "head_rise applies to head and costume.");
  if (r.floats !== undefined && s.slot !== "companion") warn("rules", "floats applies to companions.");
  if (s.slot === "companion" && typeof r.floats !== "boolean") err("rules", "A companion needs floats: true or false.");
  if (r.is_cape !== undefined && s.slot !== "back") warn("rules", "is_cape applies to back items.");
  if (r.draw !== undefined && r.draw !== "last") err("rules", 'draw is only "last".');
  if (s.slot === "held" && !r.held) warn("rules", "Held items carry rules.held (hand, grip, period...): copy one from a similar prop.");

  // Art.
  const art = s.art || {};
  const keys = Object.keys(art);
  if (!keys.length && !["aura", "bubble"].includes(s.slot)) err("art", "Upload the art (an SVG drawn on the template).");
  const allowed = SLOT_LAYERS[s.slot] || [];
  for (const key of keys) {
    const { part, cond } = parseLayerKey(key);
    if (!(LAYER_PARTS as readonly string[]).includes(part)) err("art", `Layer "${key}": unknown part "${part}".`);
    else if (!allowed.includes(part)) warn("art", `Layer "${part}" isn't drawn for the ${s.slot} slot.`);
    for (const [k, v] of Object.entries(cond)) {
      if (!CONDITIONS[k]) err("art", `Layer "${key}": unknown condition "${k}".`);
      else if (!CONDITIONS[k].includes(v)) err("art", `Layer "${key}": ${k} is one of ${CONDITIONS[k].join(", ")}.`);
    }
    for (const e of recordingErrors(art[key])) err("art", `Layer "${key}": ${e}`);
  }
  if (s.slot === "held" && !keys.some((k) => parseLayerKey(k).part === "held-body")) err("art", "A held item needs a held-body layer.");
  if (s.slot === "companion" && !keys.some((k) => parseLayerKey(k).part === "companion-body")) err("art", "A companion needs a companion-body layer.");

  // Motion and pivots.
  const bases = new Set(keys.map((k) => parseLayerKey(k).part));
  for (const [base, m] of Object.entries(s.motion || {})) {
    if (!bases.has(base)) err("motion", `Motion for "${base}", which has no art.`);
    if (!MOTION_KINDS.includes(m.kind)) err("motion", `"${base}": unknown kind.`);
    if (!isNum(m.period) || m.period <= 0 || m.period > 10) err("motion", `"${base}": period is seconds, above 0.`);
    for (const f of MOTION_FIELDS[m.kind] || []) if (!isNum(m[f.key])) err("motion", `"${base}": ${f.key} must be a number.`);
    if (PIVOTED.includes(m.kind)) {
      const has = Object.keys(s.pivots || {}).some((k) => parseLayerKey(k).part === base);
      if (!has) err("motion", `"${base}": ${m.kind} turns about pivots["${base}"]; set the pivot.`);
    }
  }
  for (const [k, p] of Object.entries(s.pivots || {})) if (!isNumArr(p, 2)) err("motion", `pivots["${k}"] needs [x, y].`);

  const size = new Blob([skinFileText(s)]).size;
  if (size > FILE_MAX) err("art", `The file is ${(size / 1024).toFixed(0)} KB; the limit is 400 KB. Simplify the art.`);
  return { errors, warnings };
}

// ---------------------------------------------------------------- template

/**
 * The drawing artboard: body units (viewBox -1.5 -1.5 3 3, Flamey's square in
 * the middle third), his plain figure as a locked reference image, and
 * labelled guides. The importer skips the `reference` and `guides` layers.
 */
export function templateSvg(plainDataUrl: string): string {
  const A = ANCHORS;
  const f = (n: number) => String(Math.round(n * 1000) / 1000);
  const hLine = (y: number, label: string, colour: string) =>
    `    <line x1="-1.5" y1="${f(y)}" x2="1.5" y2="${f(y)}" stroke="${colour}" stroke-width="0.004" stroke-dasharray="0.03 0.02"/>\n` +
    `    <text x="-1.47" y="${f(y - 0.012)}" fill="${colour}" font-size="0.045" font-family="Helvetica, Arial, sans-serif">${label} (y ${f(y)})</text>`;
  const vLine = (x: number, label: string, colour: string) =>
    `    <line x1="${f(x)}" y1="-1.5" x2="${f(x)}" y2="1.5" stroke="${colour}" stroke-width="0.004" stroke-dasharray="0.03 0.02"/>\n` +
    `    <text x="${f(x + 0.012)}" y="1.46" fill="${colour}" font-size="0.04" font-family="Helvetica, Arial, sans-serif">${label} (x ${f(x)})</text>`;
  return `<?xml version="1.0" encoding="UTF-8"?>
<!--
  Mile A Day - Flamey skin template (format 1). One unit = Flamey's body size.
  Origin (0, 0) is the centre of his square; y grows DOWN.
  Draw your item in the "art" layer, in place on him, then upload this file
  in the Skin Builder (/admin/skins). The "reference" and "guides" layers are
  ignored on upload. Keep the viewBox as it is.
  Paths, rects, circles, ellipses, lines, polylines, polygons, solid colours,
  linear/radial gradients, transforms and simple clip-paths are converted.
  Text, masks, filters and patterns are not: outline text before exporting.
  Companions: draw centred on x = 0 standing on the floor; the app moves them
  beside him. Held props: draw them in his raised hand at the right.
-->
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
     xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
     xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"
     width="768" height="768" viewBox="-1.5 -1.5 3 3">
  <g id="reference" inkscape:groupmode="layer" inkscape:label="reference" sodipodi:insensitive="true" opacity="0.6">
    <image x="-1.5" y="-1.5" width="3" height="3" preserveAspectRatio="none" xlink:href="${plainDataUrl}" href="${plainDataUrl}"/>
  </g>
  <g id="guides" inkscape:groupmode="layer" inkscape:label="guides" sodipodi:insensitive="true">
    <rect x="-0.5" y="-0.5" width="1" height="1" fill="none" stroke="#888888" stroke-width="0.004"/>
    <text x="-0.49" y="-0.51" fill="#888888" font-size="0.035" font-family="Helvetica, Arial, sans-serif">Flamey's square (1 x 1)</text>
${hLine(A.top, "top of flame", "#E0457B")}
${hLine(A.face, "face", "#4099F2")}
${hLine(A.bottom, "base", "#33B34D")}
${hLine(A.ground, "floor", "#FF9900")}
${vLine(-A.halfWidth, "body edge", "#9C6ADE")}
${vLine(A.halfWidth, "body edge", "#9C6ADE")}
    <line x1="-0.53" y1="-1.5" x2="-0.53" y2="1.5" stroke="#777777" stroke-width="0.003"/>
    <line x1="0.5" y1="-1.5" x2="0.5" y2="1.5" stroke="#777777" stroke-width="0.003"/>
    <text x="-0.52" y="-1.44" fill="#777777" font-size="0.035" font-family="Helvetica, Arial, sans-serif">hero (tight) room -0.53 to 0.5</text>
    <circle cx="0" cy="0" r="0.012" fill="#888888"/>
  </g>
  <g id="art" inkscape:groupmode="layer" inkscape:label="art">
  </g>
</svg>
`;
}
