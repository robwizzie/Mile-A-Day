// MATCH CHECK (web half): composes each item's layers around the plain figure
// with the WEBSITE's renderer (website/lib/flamey/compose.ts + skinRender.ts,
// the Skin Builder's own code) and compares the result pixel by pixel with the
// Mac's reference render of the same item (out/ref/<surface>/<id>.png). It
// reads the shipped skin files (backend/flamey-skins), so a pass means the
// files AND the web renderer draw what the Swift code drew. Colour items are
// skipped (they recolour the figure itself; the Swift match check covers them).
//
//   node match.mjs [--blur k] [--shadow k] [--only id,id] [--save]
//
// Prints one line per item and surface: % of the item's pixels that differ.
import { chromium } from 'playwright-core';
import fs from 'node:fs';
import path from 'node:path';
import { stripTypeScriptTypes } from 'node:module';

const ROOT = path.resolve(import.meta.dirname, '../../..');
const OUT = path.resolve(import.meta.dirname, '../out');
const SKINS = path.join(ROOT, 'backend/flamey-skins');
const LIB = path.join(ROOT, 'website/lib/flamey');
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const blurScale = +arg('--blur', 1), shadowScale = +arg('--shadow', 2);
const only = arg('--only', '')?.split(',').filter(Boolean);
const save = process.argv.includes('--save');
const meta = JSON.parse(fs.readFileSync(path.join(OUT, 'meta.json')));

const surfaces = ['card', 'tile', 'hero', 'widget'];

const b64 = (p) => fs.existsSync(p) ? 'data:image/png;base64,' + fs.readFileSync(p).toString('base64') : null;
const browser = await chromium.launch({
  executablePath: '/home/claude/.cache/ms-playwright/chromium_headless_shell-1234/chrome-headless-shell-linux64/chrome-headless-shell',
});
const page = await browser.newPage();
// The website's TypeScript modules, types stripped, served from a fake origin
// so their own `import ... from "./skinRender"` resolves.
const ORIGIN = 'http://flamey.local';
const emitWarning = process.emitWarning;
process.emitWarning = (w, ...rest) => (String(w).includes('stripTypeScriptTypes') ? undefined : emitWarning.call(process, w, ...rest));
await page.route(ORIGIN + '/**', (route) => {
  const url = new URL(route.request().url());
  if (url.pathname === '/') return route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>match</title>' });
  const file = path.join(LIB, path.basename(url.pathname).replace(/\.(ts|js)$/, '') + '.ts');
  if (!fs.existsSync(file)) return route.fulfill({ status: 404, body: 'not found' });
  route.fulfill({ contentType: 'text/javascript', body: stripTypeScriptTypes(fs.readFileSync(file, 'utf8')) });
});
await page.goto(ORIGIN + '/');
const webConstants = await page.evaluate(async () => {
  window.F = await import('/lib/flamey/compose');
  return window.F.CONSTANTS;
});
for (const [k, v] of Object.entries(meta.constants)) {
  if (JSON.stringify(webConstants[k]) !== JSON.stringify(v)) console.log(`WARNING constant ${k}: export says ${JSON.stringify(v)}, website/lib/flamey/compose.ts says ${JSON.stringify(webConstants[k])}`);
}

const results = [];
const ids = fs.readdirSync(SKINS).filter((f) => f.endsWith('.json')).map((f) => f.replace('.json', '')).sort();
for (const id of ids) {
  if (only.length && !only.includes(id)) continue;
  const skin = JSON.parse(fs.readFileSync(path.join(SKINS, id + '.json')));
  if (skin.slot === 'color' || skin.slot === 'bubble') continue;
  for (const s of surfaces) {
    const ref = b64(path.join(OUT, 'ref', s, id + '.png'));
    const plain = b64(path.join(OUT, 'ref', s, '_plain.png'));
    if (!ref || !plain) continue;
    const r = await page.evaluate(compose, { skin, s, ref, plain, blurScale, shadowScale, save });
    results.push({ id, surface: s, ...r });
    if (save && r.png) {
      fs.mkdirSync(path.join(OUT, 'match', s), { recursive: true });
      fs.writeFileSync(path.join(OUT, 'match', s, id + '.png'), Buffer.from(r.png.split(',')[1], 'base64'));
    }
  }
}
await browser.close();

for (const r of results) console.log(`${r.pct.toFixed(2).padStart(6)}%  ${r.surface.padEnd(6)} ${r.id}  (${r.bad}/${r.region} px)${r.note ? '  ' + r.note : ''}`);
const worst = [...results].sort((a, b) => b.pct - a.pct);
const pass = results.filter((r) => r.pct < 1).length;
console.log(`\n${pass}/${results.length} under 1%   median ${worst[Math.floor(worst.length / 2)]?.pct.toFixed(2)}%`);
fs.writeFileSync(path.join(OUT, 'match.json'), JSON.stringify(results.map(({ png, ...r }) => r), null, 1));

// Runs in the page: the website's composeLook, nothing of its own.
async function compose({ skin, s, ref, plain, blurScale, shadowScale, save }) {
  const load = (src) => new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = no; i.src = src; });
  const [refImg, plainImg] = await Promise.all([load(ref), load(plain)]);
  const W = refImg.width, H = refImg.height;
  const F = window.F;
  const surface = F.SURFACES.find((x) => x.name === s);
  if (!F.drawsOn(skin, surface)) return { pct: 0, bad: 0, region: 0, note: 'not on compact' };
  const cv = new OffscreenCanvas(W, H);
  const ctx = cv.getContext('2d');
  const images = await F.loadSkinImages(skin);
  F.composeLook(ctx, W, skin, surface, { plain: plainImg, images }, { blurScale, shadowScale, time: null });

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
