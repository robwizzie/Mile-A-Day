// The phone remote's live preview runs a copy of the desk counter's code
// (website/public/desk/py/mad). It must match desk/firmware/mad exactly, or
// the preview would show something the boxes don't. Fix: desk/sync-preview.sh
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const src = path.join(root, "desk/firmware/mad");
const dst = path.join(root, "website/public/desk/py/mad");
let bad = 0;
for (const f of fs.readdirSync(src).filter((f) => f.endsWith(".py") && f !== "main.py")) {
  const a = fs.readFileSync(path.join(src, f));
  const b = fs.existsSync(path.join(dst, f)) ? fs.readFileSync(path.join(dst, f)) : null;
  if (!b || !a.equals(b)) {
    console.log(`FAIL  ${f} differs (run desk/sync-preview.sh)`);
    bad++;
  }
}
console.log(bad ? `desk-preview-check: ${bad} FAILED` : "desk-preview-check: all assertions passed");
process.exit(bad ? 1 : 0);
