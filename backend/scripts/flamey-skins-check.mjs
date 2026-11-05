/**
 * Flamey skins check — every file in backend/flamey-skins/ (docs/flamey-skins.md).
 *
 * Pure file checks, no database. Fails on:
 *   - invalid JSON, id != filename, a missing required field, an unknown slot,
 *     a non-positive-integer format, a malformed unlock, duplicate ids/orders;
 *   - malformed art: op not fill|stroke|image, path data beyond M L Q C Z +
 *     numbers, paint not #RRGGBBAA / {tok,a,fb} / lin|rad|conic gradient with
 *     stops, clip index out of range, image src missing from `images`;
 *   - parity with flameyCatalog.ts ROWS (the migration): every ROWS id has a
 *     file with the SAME slot and unlock;
 *   - a badge unlock whose badge isn't seeded (badges-seed.sql +
 *     seedExtraBadges, holidays included — the same catalog the closet check
 *     seeds into Postgres);
 *   - any file over 400 KB, or the folder over 5 MB.
 *
 * Needs `npm run build` first (reads ROWS / slots / extra badges from dist).
 * Usage: node scripts/flamey-skins-check.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const DIR = process.env.FLAMEY_SKINS_DIR ?? path.resolve(here, "../flamey-skins");
const FILE_MAX = 400 * 1024;
const DIR_MAX = 5 * 1024 * 1024;
const REQUIRED = [
  "format", "id", "order", "slot", "name", "family", "unlock", "unlock_copy",
  "holidays", "mood_prop", "compact", "rules", "art",
];

let catalog, badges;
try {
  catalog = await import("../dist/services/flameyCatalog.js");
  badges = await import("../dist/services/badgeService.js");
} catch (e) {
  console.error(`FAIL  cannot load dist/ (run \`npm run build\` first): ${e?.message ?? e}`);
  process.exit(1);
}
const { FLAMEY_SLOTS, FLAMEY_ROW_ITEMS } = catalog;

const errors = [];
const fail = (file, msg) => errors.push(`${file}: ${msg}`);

// ── Seeded badge ids: badges-seed.sql rows + seedExtraBadges (incl. holidays).
const seedSql = fs.readFileSync(path.join(here, "badges-seed.sql"), "utf8");
const seeded = new Set(badges.extraBadgeIds());
for (const m of seedSql.matchAll(/^\s*\(\s*'([a-z0-9_]+)'\s*,/gm)) seeded.add(m[1]);

// ── Validators.
const HEX = /^#[0-9A-Fa-f]{8}$/;
const NUM = "-?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?";
const PATH_RE = new RegExp(`^(?:\\s*(?:[MLQCZ]|${NUM})(?:\\s*,)?)*\\s*$`);
const isNum = (v) => typeof v === "number" && Number.isFinite(v);
const isNumArr = (v, n) => Array.isArray(v) && (n === undefined || v.length === n) && v.every(isNum);

function pathError(d) {
  if (typeof d !== "string" || !d.length) return "d missing";
  if (!PATH_RE.test(d)) return `d has commands outside M L Q C Z: ${JSON.stringify(d.slice(0, 40))}`;
  if (!/^\s*M/.test(d)) return "d must start with M";
  return null;
}

function colorError(c) {
  if (typeof c === "string") return HEX.test(c) ? null : `colour ${JSON.stringify(c)} not #RRGGBBAA`;
  if (c && typeof c === "object" && !Array.isArray(c) && "tok" in c) {
    if (typeof c.tok !== "string" || !c.tok) return "token without tok";
    if ("a" in c && !isNum(c.a)) return "token a not a number";
    if ("fb" in c && !(typeof c.fb === "string" && HEX.test(c.fb))) return "token fb not #RRGGBBAA";
    const extra = Object.keys(c).filter((k) => !["tok", "a", "fb"].includes(k));
    return extra.length ? `token has unknown keys ${extra}` : null;
  }
  return `bad colour ${JSON.stringify(c)?.slice(0, 60)}`;
}

function paintError(p) {
  if (p === undefined) return "paint missing";
  if (typeof p === "string" || (p && typeof p === "object" && "tok" in p)) return colorError(p);
  if (!p || typeof p !== "object" || Array.isArray(p)) return "bad paint";
  const kind = ["lin", "rad", "conic"].filter((k) => k in p);
  if (kind.length !== 1) return `paint is not a colour, token or one gradient: ${JSON.stringify(p).slice(0, 60)}`;
  const n = { lin: 4, rad: 4, conic: 3 }[kind[0]];
  if (!isNumArr(p[kind[0]], n)) return `${kind[0]} needs ${n} numbers`;
  if (!Array.isArray(p.stops) || p.stops.length < 1) return `${kind[0]} gradient without stops`;
  for (const s of p.stops) {
    if (!Array.isArray(s) || s.length !== 2 || !isNum(s[0])) return "stop must be [t, colour]";
    const e = colorError(s[1]);
    if (e) return `stop ${e}`;
  }
  return null;
}

function recordingErrors(rec) {
  const out = [];
  if (!rec || typeof rec !== "object" || !Array.isArray(rec.ops)) return ["recording without ops[]"];
  const clips = rec.clips ?? [];
  if (!Array.isArray(clips)) out.push("clips not an array");
  else clips.forEach((c, i) => {
    const e = pathError(c?.d);
    if (e) out.push(`clips[${i}] ${e}`);
  });
  const images = rec.images ?? {};
  for (const [k, v] of Object.entries(images)) {
    if (typeof v !== "string" || !v.startsWith("data:image/")) out.push(`images.${k} not a data:image URL`);
  }
  rec.ops.forEach((o, i) => {
    const at = `ops[${i}]`;
    if (!o || typeof o !== "object") return out.push(`${at} not an object`);
    if (!["fill", "stroke", "image"].includes(o.op)) return out.push(`${at} op ${JSON.stringify(o.op)}`);
    if (o.op === "image") {
      if (typeof o.src !== "string" || !(o.src in images)) out.push(`${at} image src ${JSON.stringify(o.src)} not in images`);
      if (!isNumArr(o.rect, 4)) out.push(`${at} image rect needs 4 numbers`);
    } else {
      const pe = pathError(o.d);
      if (pe) out.push(`${at} ${pe}`);
      const pa = paintError(o.paint);
      if (pa) out.push(`${at} ${pa}`);
      if (o.op === "stroke" && !isNum(o.w)) out.push(`${at} stroke without w`);
    }
    if ("m" in o && !isNumArr(o.m, 6)) out.push(`${at} m needs 6 numbers`);
    if ("a" in o && !isNum(o.a)) out.push(`${at} a not a number`);
    if ("clip" in o) {
      if (!Array.isArray(o.clip) || !o.clip.every((c) => Number.isInteger(c) && c >= 0 && c < clips.length)) {
        out.push(`${at} clip ${JSON.stringify(o.clip)} out of range (${clips.length} clips)`);
      }
    }
    if ("fx" in o) {
      if (!Array.isArray(o.fx)) out.push(`${at} fx not an array`);
      else for (const f of o.fx) {
        const ok = (f && isNum(f.blur) && Object.keys(f).length === 1) ||
          (f && Array.isArray(f.shadow) && f.shadow.length === 4 && HEX.test(f.shadow[0]) &&
            f.shadow.slice(1).every(isNum) && Object.keys(f).length === 1);
        if (!ok) out.push(`${at} bad fx ${JSON.stringify(f).slice(0, 60)}`);
      }
    }
  });
  return out;
}

function unlockKey(u) {
  if (u === "always" || u === "plus") return u;
  if (u && typeof u === "object" && !Array.isArray(u)) {
    const keys = Object.keys(u);
    if (keys.length === 1 && typeof u.badge === "string" && u.badge) return `badge:${u.badge}`;
    if (keys.length === 1 && Number.isInteger(u.month) && u.month >= 1 && u.month <= 12) return `month:${u.month}`;
  }
  return null;
}
const itemUnlockKey = (u) =>
  u.kind === "badge" ? `badge:${u.id}` : u.kind === "month" ? `month:${u.month}` : u.kind;

// ── Walk the folder.
const files = fs.readdirSync(DIR).filter((f) => f.endsWith(".json")).sort();
const stray = fs.readdirSync(DIR).filter((f) => !f.endsWith(".json") && !f.startsWith("."));
for (const f of stray) fail(f, "not a .json file");

let totalBytes = 0;
let largest = { file: "", bytes: 0 };
const ids = new Map();
const orders = new Map();
const skins = new Map();
for (const file of files) {
  const full = path.join(DIR, file);
  const bytes = fs.statSync(full).size;
  totalBytes += bytes;
  if (bytes > largest.bytes) largest = { file, bytes };
  if (bytes > FILE_MAX) fail(file, `${(bytes / 1024).toFixed(0)} KB > 400 KB`);

  let j;
  try {
    j = JSON.parse(fs.readFileSync(full, "utf8"));
  } catch (e) {
    fail(file, `invalid JSON (${e.message})`);
    continue;
  }
  if (!j || typeof j !== "object" || Array.isArray(j)) {
    fail(file, "not an object");
    continue;
  }
  const missing = REQUIRED.filter((k) => !(k in j));
  if (missing.length) fail(file, `missing ${missing.join(", ")}`);
  const id = path.basename(file, ".json");
  if (j.id !== id) fail(file, `id ${JSON.stringify(j.id)} != filename`);
  if (!/^[a-z0-9_]+$/.test(id)) fail(file, "id must be [a-z0-9_]+");
  if (!Number.isInteger(j.format) || j.format < 1) fail(file, `format ${JSON.stringify(j.format)} not a positive integer`);
  if (!isNum(j.order)) fail(file, `order ${JSON.stringify(j.order)} not a number`);
  if (!FLAMEY_SLOTS.includes(j.slot)) fail(file, `slot ${JSON.stringify(j.slot)} not in FLAMEY_SLOTS`);
  if (typeof j.name !== "string" || !j.name.trim()) fail(file, "name must be a non-empty string");
  if (typeof j.family !== "string") fail(file, "family must be a string");
  if (typeof j.unlock_copy !== "string") fail(file, "unlock_copy must be a string");
  if (!Array.isArray(j.holidays) || !j.holidays.every((h) => typeof h === "string")) fail(file, "holidays must be string[]");
  if (typeof j.mood_prop !== "boolean") fail(file, "mood_prop must be boolean");
  if (typeof j.compact !== "boolean") fail(file, "compact must be boolean");
  if (!j.rules || typeof j.rules !== "object" || Array.isArray(j.rules)) fail(file, "rules must be an object");
  const uk = unlockKey(j.unlock);
  if (!uk) fail(file, `bad unlock ${JSON.stringify(j.unlock)}`);
  else if (uk.startsWith("badge:") && !seeded.has(uk.slice(6))) fail(file, `unlock badge ${uk.slice(6)} is not a seeded badge`);

  if (typeof j.id === "string") {
    if (ids.has(j.id)) fail(file, `duplicate id (also ${ids.get(j.id)})`);
    ids.set(j.id, file);
  }
  if (isNum(j.order)) {
    if (orders.has(j.order)) fail(file, `duplicate order ${j.order} (also ${orders.get(j.order)})`);
    orders.set(j.order, file);
  }

  if (!j.art || typeof j.art !== "object" || Array.isArray(j.art)) fail(file, "art must be an object");
  else {
    for (const [layer, rec] of Object.entries(j.art)) {
      for (const e of recordingErrors(rec)) fail(file, `art["${layer}"].${e}`);
    }
  }
  skins.set(id, { slot: j.slot, unlock: uk });
}
if (totalBytes > DIR_MAX) fail("flamey-skins/", `folder ${(totalBytes / 1048576).toFixed(2)} MB > 5 MB`);

// ── Parity with ROWS: every built-in item has a file with the same slot + unlock.
let parity = 0;
for (const item of FLAMEY_ROW_ITEMS.values()) {
  const s = skins.get(item.id);
  if (!s) {
    fail(`${item.id}.json`, "ROWS item has no skin file");
    continue;
  }
  if (s.slot !== item.slot) fail(`${item.id}.json`, `slot ${s.slot} != ROWS ${item.slot}`);
  const want = itemUnlockKey(item.unlock);
  if (s.unlock !== want) fail(`${item.id}.json`, `unlock ${s.unlock} != ROWS ${want}`);
  parity++;
}

for (const e of errors) console.log(`FAIL  ${e}`);
const newItems = [...skins.keys()].filter((id) => !FLAMEY_ROW_ITEMS.has(id)).length;
const summary =
  `${files.length} skins, ${(totalBytes / 1048576).toFixed(2)} MB ` +
  `(largest ${largest.file} ${(largest.bytes / 1024).toFixed(0)} KB), ` +
  `${parity}/${FLAMEY_ROW_ITEMS.size} ROWS items matched, ${newItems} beyond ROWS`;
if (errors.length) {
  console.log(`flamey-skins-check: FAILED — ${errors.length} problem(s); ${summary}`);
  process.exit(1);
}
console.log(`flamey-skins-check: OK — ${summary}`);
process.exit(0);
