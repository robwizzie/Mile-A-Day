// MATCH CHECK (web half): composes each item's recorded layers around the
// plain figure exactly as FlameyOutfitLayer does for a one-item look, and
// compares the result pixel by pixel with the Mac's reference render of the
// same item (out/ref/<surface>/<id>.png). Colour items are skipped (they
// recolour the figure itself; the Swift match check covers them).
//
//   node match.mjs [--blur k] [--shadow k] [--only id,id] [--save]
//
// Prints one line per item and surface: % of the item's pixels that differ.
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';

const OUT = path.resolve(import.meta.dirname, '../out');
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const blurScale = +arg('--blur', 1), shadowScale = +arg('--shadow', 2);
const only = arg('--only', '')?.split(',').filter(Boolean);
const save = process.argv.includes('--save');
const meta = JSON.parse(fs.readFileSync(path.join(OUT, 'meta.json')));
const C = meta.constants;

const surfaces = [
  { name: 'card', reach: 0.9, compact: false },
  { name: 'tile', reach: 0.8, compact: false },
  { name: 'hero', reach: 0.62, compact: false },
  { name: 'widget', reach: 0.9, compact: true },
];

const b64 = (p) => fs.existsSync(p) ? 'data:image/png;base64,' + fs.readFileSync(p).toString('base64') : null;
const browser = await chromium.launch({
  executablePath: '/home/claude/.cache/ms-playwright/chromium_headless_shell-1234/chrome-headless-shell-linux64/chrome-headless-shell',
});
const page = await browser.newPage();
await page.addScriptTag({ content: fs.readFileSync(path.join(import.meta.dirname, 'skin-render.js'), 'utf8') });

const results = [];
const ids = fs.readdirSync(path.join(OUT, 'skins-raw')).map((f) => f.replace('.json', '')).sort();
for (const id of ids) {
  if (only.length && !only.includes(id)) continue;
  const skin = JSON.parse(fs.readFileSync(path.join(OUT, 'skins-raw', id + '.json')));
  if (skin.slot === 'color' || skin.slot === 'bubble') continue;
  for (const s of surfaces) {
    const ref = b64(path.join(OUT, 'ref', s.name, id + '.png'));
    const plain = b64(path.join(OUT, 'ref', s.name, '_plain.png'));
    if (!ref || !plain) continue;
    const r = await page.evaluate(compose, { skin, s, ref, plain, C, blurScale, shadowScale, save });
    results.push({ id, surface: s.name, ...r });
    if (save && r.png) {
      fs.mkdirSync(path.join(OUT, 'match', s.name), { recursive: true });
      fs.writeFileSync(path.join(OUT, 'match', s.name, id + '.png'), Buffer.from(r.png.split(',')[1], 'base64'));
    }
  }
}
await browser.close();

for (const r of results) console.log(`${r.pct.toFixed(2).padStart(6)}%  ${r.surface.padEnd(6)} ${r.id}  (${r.bad}/${r.region} px)${r.note ? '  ' + r.note : ''}`);
const worst = [...results].sort((a, b) => b.pct - a.pct);
const pass = results.filter((r) => r.pct < 1).length;
console.log(`\n${pass}/${results.length} under 1%   median ${worst[Math.floor(worst.length / 2)]?.pct.toFixed(2)}%`);
fs.writeFileSync(path.join(OUT, 'match.json'), JSON.stringify(results.map(({ png, ...r }) => r), null, 1));

// Runs in the page.
async function compose({ skin, s, ref, plain, C, blurScale, shadowScale, save }) {
  const load = (src) => new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = no; i.src = src; });
  const [refImg, plainImg] = await Promise.all([load(ref), load(plain)]);
  const W = refImg.width, H = refImg.height;
  const U = W / 3; // px per body unit: stage = 3S, u = S at body scale 1
  const cv = new OffscreenCanvas(W, H);
  const ctx = cv.getContext('2d');
  const art = skin.art || {};
  const images = {};
  for (const rec of Object.values(art)) for (const [k, src] of Object.entries(rec.images || {})) images[k] = await load(src);
  const R = FlameySkinRender;
  const opts = { blurScale, shadowScale };
  const reach = s.reach;
  const rk = String(reach);
  const tight = reach < C.tight_reach;
  const slot = skin.slot;
  if (s.compact && !skin.compact) return { pct: 0, bad: 0, region: 0, note: 'not on compact' };

  function body(fn) {
    ctx.save();
    ctx.translate(W / 2, H / 2);
    ctx.scale(U, U);
    if (s.compact) { ctx.translate(0, 0.5); ctx.scale(1 / (1 + C.leg_length), 1 / (1 + C.leg_length)); ctx.translate(0, -0.5); }
    if (tight) {
      // FlameyOutfitLayer's tight mask: a band as wide as his room (hard edge here).
      const [l, r] = C.tight_mask_bounds;
      ctx.beginPath(); ctx.rect(l, -5, r - l, 10); ctx.clip();
    }
    fn();
    ctx.restore();
  }

  // Behind.
  body(() => {
    if (slot === 'trail') {
      ctx.save();
      if (tight) ctx.scale(C.trail_tuck, 1);
      R.drawLayer(ctx, art[`behind@reach=${rk},low=0`], opts, images);
      ctx.restore();
    }
    if (slot === 'back') {
      R.drawLayer(ctx, art[`behind@reach=${rk}`] || art[`behind@reach=${rk},glow=1`], opts, images);
    }
  });
  // A hovering look (rocket boots, winged sandals) lifts the whole figure.
  const hover = slot === 'feet' && !s.compact ? (skin.hover_lift || 0) : 0;
  ctx.drawImage(plainImg, 0, -hover * U);
  // Front.
  body(() => {
    const front = slot === 'feet' ? art[`front@jets=${s.compact ? 0 : 1}`] : art.front;
    R.drawLayer(ctx, front, opts, images);
    R.drawLayer(ctx, art['bopper-band'], opts, images);
    R.drawLayer(ctx, art['bopper-springs'], opts, images);
    if (slot === 'held') {
      R.drawLayer(ctx, art[`held-body@reach=${rk}`], opts, images);
      R.drawLayer(ctx, art[`held-accent@reach=${rk}`], opts, images);
    }
    if (slot === 'companion') {
      const floats = !!skin.floats;
      const k = tight ? 0.60 : 1.15;
      const x = tight ? (floats ? 0.30 : 0.26) : Math.max(0.56, Math.min(0.70, reach - 0.14));
      const lift = tight && floats ? -0.42 : 0;
      const g = 0.5; // ground
      const place = (dy, rec) => {
        ctx.save(); ctx.translate(x, dy); ctx.translate(0, g); ctx.scale(k, k); ctx.translate(0, -g);
        R.drawLayer(ctx, rec, opts, images); ctx.restore();
      };
      if (!(tight && floats)) place(0, art['companion-shadow']);
      place(lift, art['companion-body@pose=rest']);
    }
  });

  // Compare against the reference, over the pixels where either differs from plain.
  const get = (img) => { const c = new OffscreenCanvas(W, H); const x = c.getContext('2d'); x.drawImage(img, 0, 0); return x.getImageData(0, 0, W, H).data; };
  const a = ctx.getImageData(0, 0, W, H).data, b = get(refImg), p = get(plainImg);
  const T = 40;
  const dist = (u, v, i) => Math.max(Math.abs(u[i] * u[i + 3] - v[i] * v[i + 3]), Math.abs(u[i + 1] * u[i + 3] - v[i + 1] * v[i + 3]),
    Math.abs(u[i + 2] * u[i + 3] - v[i + 2] * v[i + 3])) / 255 + 0 * 0 + Math.abs(u[i + 3] - v[i + 3]) * 0;
  let region = 0, bad = 0;
  const diff = save ? new OffscreenCanvas(W, H) : null;
  const dctx = diff?.getContext('2d'); const dimg = dctx?.createImageData(W, H);
  for (let i = 0; i < a.length; i += 4) {
    const inRegion = dist(b, p, i) > T || dist(a, p, i) > T || Math.abs(b[i + 3] - p[i + 3]) > T || Math.abs(a[i + 3] - p[i + 3]) > T;
    if (!inRegion) continue;
    region++;
    // Off only if no reference pixel within 1px matches (antialiasing on
    // thin lines shifts by half a pixel between renderers).
    let off = true;
    const px = (i / 4) % W, py = Math.floor(i / 4 / W);
    for (let dy = -1; dy <= 1 && off; dy++) for (let dx = -1; dx <= 1 && off; dx++) {
      const qx = px + dx, qy = py + dy;
      if (qx < 0 || qy < 0 || qx >= W || qy >= H) continue;
      const j = (qy * W + qx) * 4;
      if (!(Math.max(Math.abs(a[i] * a[i + 3] - b[j] * b[j + 3]), Math.abs(a[i + 1] * a[i + 3] - b[j + 1] * b[j + 3]),
        Math.abs(a[i + 2] * a[i + 3] - b[j + 2] * b[j + 3])) / 255 > T || Math.abs(a[i + 3] - b[j + 3]) > T)) off = false;
    }
    if (off) bad++;
    if (dimg) { dimg.data[i] = off ? 255 : 0; dimg.data[i + 1] = off ? 0 : 160; dimg.data[i + 2] = 0; dimg.data[i + 3] = 255; }
  }
  let png = null;
  if (save) {
    // [reference | ours | diff]
    const out = new OffscreenCanvas(W * 3, H);
    const o = out.getContext('2d');
    o.fillStyle = '#1e1e22'; o.fillRect(0, 0, W * 3, H);
    o.drawImage(refImg, 0, 0); o.drawImage(cv, W, 0);
    dctx.putImageData(dimg, 0, 0); o.drawImage(diff, W * 2, 0);
    const blob = await out.convertToBlob();
    png = await new Promise((ok) => { const fr = new FileReader(); fr.onload = () => ok(fr.result); fr.readAsDataURL(blob); });
  }
  return { pct: region ? (100 * bad) / region : 0, bad, region, png };
}
