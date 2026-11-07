// Writes the copy of every skin the app ships with (offline first launch,
// widgets, Watch) from backend/flamey-skins, byte-identical and minified.
//
//   node bundle.mjs           write both
//   node bundle.mjs --check   exit 1 if either is stale (CI)
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const ROOT = path.resolve(import.meta.dirname, '../../..');
const SRC = path.join(ROOT, 'backend/flamey-skins');
const DESTS = ['app/Mile A Day/FlameySkins.json', 'app/MileADayWidgets/FlameySkins.json', 'app/Mile A Day Watch Watch App/Flamey/FlameySkins.json'].map((p) => path.join(ROOT, p));

const files = fs.readdirSync(SRC).filter((f) => f.endsWith('.json')).sort();
const skins = files.map((f) => JSON.parse(fs.readFileSync(path.join(SRC, f), 'utf8')))
  .sort((a, b) => a.order - b.order || a.id.localeCompare(b.id));
const body = JSON.stringify(skins);
const version = crypto.createHash('sha256').update(body).digest('hex').slice(0, 16);
const text = JSON.stringify({ version, skins }) + '\n';

let stale = 0;
for (const d of DESTS) {
  const cur = fs.existsSync(d) ? fs.readFileSync(d, 'utf8') : null;
  if (cur === text) continue;
  stale++;
  if (!process.argv.includes('--check')) fs.writeFileSync(d, text);
}
console.log(`${skins.length} skins, version ${version}, ${(text.length / 1024).toFixed(0)} KB; ${process.argv.includes('--check') ? `${stale} stale` : `wrote ${stale}`}`);
if (process.argv.includes('--check') && stale) {
  console.log('Run: node app/FlameyExport/convert/bundle.mjs');
  process.exit(1);
}
