// Turns the exporter's raw recordings (app/FlameyExport/out/skins-raw) into
// the skin files the backend serves (backend/flamey-skins/<id>.json, format
// in docs/flamey-skins.md). What the Swift code decided per item in
// FlameyRender.swift (motion, draw order, the month crowns, the wings' glow)
// is written here as data, once, so the renderer has no per-item code.
//
//   node assemble.mjs            write the files
//   node assemble.mjs --check    exit 1 if any file would change
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '../../..');
const RAW = path.join(ROOT, 'app/FlameyExport/out/skins-raw');
const DEST = path.join(ROOT, 'backend/flamey-skins');
const check = process.argv.includes('--check');

// Unlocks come from the backend catalog — the server decides ownership.
const catalogSrc = fs.readFileSync(path.join(ROOT, 'backend/src/services/flameyCatalog.ts'), 'utf8');
const serverUnlock = new Map();
for (const m of catalogSrc.matchAll(/\[\s*"([a-z0-9_]+)",\s*"([a-z]+)",\s*"([^"]+)"\s*\]/g)) {
  const [, id, slot, u] = m;
  let unlock;
  if (u === 'always' || u === 'plus') unlock = u;
  else if (u.startsWith('month:')) unlock = { month: Number(u.slice(6)) };
  else unlock = { badge: u };
  serverUnlock.set(id, { slot, unlock });
}

// Closet order = FlameyItem's case order (the exporter records it too; this
// covers exports made before it did).
const wardrobe = fs.readFileSync(path.join(ROOT, 'app/MileADayWidgets/FlameyWardrobe.swift'), 'utf8');
const enumBody = wardrobe.slice(wardrobe.indexOf('enum FlameyItem'), wardrobe.indexOf('static var closet'));
const enumOrder = [];
for (const line of enumBody.split('\n')) {
  const code = line.replace(/\/\/.*$/, '');
  const m = code.match(/^\s*case\s+(.*)$/) || (enumOrder.length && code.match(/^\s{6,}([a-z].*)$/));
  if (!m) continue;
  for (const part of m[1].split(',')) {
    const t = part.trim();
    if (!t) continue;
    const eq = t.match(/^(\w+)\s*=\s*"([^"]+)"/);
    enumOrder.push(eq ? eq[2] : t.replace(/\W.*$/, ''));
  }
}

const AURAS = new Set(['spectral_glow', 'flicker', 'spotlight', 'paparazzi']);
const problems = [];
const written = [];

for (const file of fs.readdirSync(RAW).filter((f) => f.endsWith('.json')).sort()) {
  const raw = JSON.parse(fs.readFileSync(path.join(RAW, file)));
  const id = raw.id;
  const server = serverUnlock.get(id);
  if (!raw.mood_prop) {
    if (!server) problems.push(`${id}: in the app but not in backend flameyCatalog.ts`);
    else if (server.slot !== raw.slot) problems.push(`${id}: slot ${raw.slot} in the app, ${server.slot} on the server`);
  }

  const rules = {
    hides: raw.hides,
    clashes: raw.clashes,
  };
  if (raw.hover_lift) rules.hover_lift = raw.hover_lift;
  if (raw.head_rise) rules.head_rise = raw.head_rise;
  if (raw.head_scale !== undefined && raw.head_scale !== 1) rules.head_scale = raw.head_scale;
  if (raw.is_cape) rules.is_cape = true;
  if (raw.slot === 'companion') rules.floats = !!raw.floats;
  if (raw.shows_face === false) rules.shows_face = false;
  if (raw.shows_arms === false) rules.shows_arms = false;
  if (raw.figure_palette) rules.figure_palette = raw.figure_palette;
  if (raw.held) rules.held = raw.held;
  if (raw.arm_hold && Object.keys(raw.arm_hold).length) rules.arm_hold = raw.arm_hold;
  // FlameyRender: the astronaut helmet goes on last, over chest, eyes and head.
  if (id === 'astronaut_helmet') rules.draw = 'last';
  // FlameyArt.monthCrown/monthCrownRise: these colours wear a little crown
  // when nothing is on his head.
  if (raw.art?.crown) {
    rules.crown_unless = ['head', 'costume'];
    rules.crown_rise = id === 'twinkle_lights' ? 0.13 : 0.07;
  }
  // FlameyLook.glow: golden wings are his one halo-class effect.
  if (id === 'golden_wings') rules.glow = 'wings';

  const motion = {};
  if (raw.slot === 'trail') motion.behind = { kind: 'drift', dx: -0.035, dx_tight: -0.015, alpha: 0.78, period: 1.6 };
  if (raw.slot === 'companion') motion['companion-body'] = { kind: 'bob', dy: raw.floats ? -0.05 : -0.02, period: 1.6 };
  if (raw.art?.['bopper-springs']) motion['bopper-springs'] = { kind: 'sway', deg: 6, period: 1.6 };
  if (raw.slot === 'held' && raw.held) {
    const h = raw.held;
    motion['held-body'] = id === 'pom_poms'
      ? { kind: 'pump', scale: 1.07, dy: -0.012, period: h.period }
      : { kind: 'wobble', deg: h.wobble, back: 0.35, period: h.period };
    if (h.accent && h.accent !== 'none') motion['held-accent'] = { kind: h.accent, period: h.period };
  }

  const effects = [];
  if (raw.slot === 'aura' && AURAS.has(id)) effects.push(`aura:${id}`);
  if (raw.slot === 'bubble') effects.push(`bubble:${id}`);

  // Empty layers carry nothing (the heart bopper's `front` is its two parts).
  const art = {};
  for (const [k, rec] of Object.entries(raw.art || {})) {
    if (rec.ops && rec.ops.length) {
      const { palette_tokens, ...clean } = rec;
      art[k] = clean;
    }
  }

  const skin = {
    format: 1,
    id,
    order: raw.order ?? enumOrder.indexOf(id),
    slot: raw.slot,
    name: raw.name,
    family: raw.family,
    unlock: server?.unlock ?? 'always',
    unlock_copy: raw.unlock_copy,
    holidays: raw.holidays,
    mood_prop: raw.mood_prop,
    compact: raw.compact,
    rules,
  };
  if (raw.palette) skin.palette = raw.palette;
  if (effects.length) skin.effects = effects;
  skin.art = art;
  if (raw.pivots && Object.keys(raw.pivots).length) skin.pivots = raw.pivots;
  if (Object.keys(motion).length) skin.motion = motion;

  const text = stringify(skin) + '\n';
  const dest = path.join(DEST, `${id}.json`);
  const before = fs.existsSync(dest) ? fs.readFileSync(dest, 'utf8') : null;
  if (before !== text) {
    written.push(id);
    if (!check) {
      fs.mkdirSync(DEST, { recursive: true });
      fs.writeFileSync(dest, text);
    }
  }
}

for (const id of serverUnlock.keys()) {
  if (!fs.existsSync(path.join(RAW, `${id}.json`))) problems.push(`${id}: on the server but the exporter didn't record it`);
}

if (enumOrder.length !== new Set(enumOrder).size) problems.push('FlameyItem case order parsed with duplicates');

for (const p of problems) console.log('PROBLEM ' + p);
console.log(`${check ? 'would change' : 'wrote'} ${written.length} file(s); ${problems.length} problem(s)`);
if (problems.length || (check && written.length)) process.exit(1);

// Pretty at the top, one op per line inside recordings: small files whose
// diffs read item by item.
function stringify(v, indent = '') {
  const next = indent + '  ';
  if (Array.isArray(v)) {
    if (v.every((x) => x === null || typeof x !== 'object')) return JSON.stringify(v);
    if (v.every((x) => x && typeof x === 'object' && !Array.isArray(x) && ('op' in x || 'd' in x))) {
      return '[\n' + v.map((x) => next + JSON.stringify(x)).join(',\n') + '\n' + indent + ']';
    }
    return '[\n' + v.map((x) => next + stringify(x, next)).join(',\n') + '\n' + indent + ']';
  }
  if (v && typeof v === 'object') {
    const keys = Object.keys(v);
    if (!keys.length) return '{}';
    if (keys.every((k) => v[k] === null || typeof v[k] !== 'object' || (Array.isArray(v[k]) && v[k].every((x) => typeof x !== 'object')))
      && JSON.stringify(v).length < 100) return JSON.stringify(v);
    return '{\n' + keys.map((k) => next + JSON.stringify(k) + ': ' + stringify(v[k], next)).join(',\n') + '\n' + indent + '}';
  }
  return JSON.stringify(v);
}
