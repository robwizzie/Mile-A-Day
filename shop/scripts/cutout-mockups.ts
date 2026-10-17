// Turns Tapstitch flat-lay mockups (garment on white) into the transparent
// garment photos the rack hangs:
//
//   npm run cutouts -- <dir>
//
// <dir> holds <product-id>-front.png and <product-id>-back.png, as downloaded
// from the design's page in Tapstitch. Writes public/garments/<id>-front.webp
// and -back.webp, both cropped to the same box so the piece doesn't jump when
// it turns around, and prints each pair's aspect for lib/catalog.ts.

import sharp from "sharp";
import { readdir } from "node:fs/promises";
import { join } from "node:path";

const OUT = join(process.cwd(), "public/garments");
/** How far from pure white a pixel may be and still count as background. */
const TOLERANCE = 7;
const WIDTH = 1210; // matches the hoodie photos
const INSET = 8;

async function cutout(file: string) {
  // Some mockups have a hairline gray frame; shave it so the fill starts on white.
  const meta = await sharp(file).metadata();
  const { data, info } = await sharp(file)
    .extract({ left: INSET, top: INSET, width: meta.width! - 2 * INSET, height: meta.height! - 2 * INSET })
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width: w, height: h } = info;
  const bg = new Uint8Array(w * h);
  const near = (i: number) => 255 - Math.min(data[i * 3], data[i * 3 + 1], data[i * 3 + 2]) <= TOLERANCE;

  // Flood fill the white that touches the border; white inside the garment
  // (prints, a white tee's body) is walled off by its outline and stays.
  const stack: number[] = [];
  for (let x = 0; x < w; x++) stack.push(x, (h - 1) * w + x);
  for (let y = 0; y < h; y++) stack.push(y * w, y * w + w - 1);
  while (stack.length) {
    const i = stack.pop()!;
    if (bg[i] || !near(i)) continue;
    bg[i] = 1;
    const x = i % w;
    if (x > 0) stack.push(i - 1);
    if (x < w - 1) stack.push(i + 1);
    if (i >= w) stack.push(i - w);
    if (i < w * (h - 1)) stack.push(i + w);
  }

  // Alpha is a 3×3 average of the mask, which softens the edge by a pixel so
  // it doesn't look clipped.
  const raw = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      let solid = 0, n = 0;
      for (let dy = -1; dy <= 1; dy++)
        for (let dx = -1; dx <= 1; dx++) {
          const yy = y + dy, xx = x + dx;
          if (yy < 0 || yy >= h || xx < 0 || xx >= w) continue;
          n++;
          if (!bg[yy * w + xx]) solid++;
        }
      raw[i * 4] = data[i * 3];
      raw[i * 4 + 1] = data[i * 3 + 1];
      raw[i * 4 + 2] = data[i * 3 + 2];
      raw[i * 4 + 3] = Math.round((255 * solid) / n);
    }
  const rgba = await sharp(raw, { raw: { width: w, height: h, channels: 4 } }).png().toBuffer();

  let top = h, left = w, bottom = 0, right = 0;
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++)
      if (!bg[y * w + x]) {
        if (y < top) top = y;
        if (y > bottom) bottom = y;
        if (x < left) left = x;
        if (x > right) right = x;
      }
  return { rgba, box: { top, left, bottom, right } };
}

async function main() {
  const dir = process.argv[2];
  if (!dir) throw new Error("usage: npm run cutouts -- <dir with <id>-front.png / <id>-back.png>");
  const ids = (await readdir(dir)).filter((f) => f.endsWith("-front.png")).map((f) => f.replace(/-front\.png$/, ""));

  for (const id of ids) {
    const [front, back] = await Promise.all([cutout(join(dir, `${id}-front.png`)), cutout(join(dir, `${id}-back.png`))]);
    const left = Math.min(front.box.left, back.box.left);
    const top = Math.min(front.box.top, back.box.top);
    const width = Math.max(front.box.right, back.box.right) - left + 1;
    const height = Math.max(front.box.bottom, back.box.bottom) - top + 1;
    for (const [side, cut] of [["front", front], ["back", back]] as const) {
      await sharp(cut.rgba)
        .extract({ left, top, width, height })
        .resize({ width: WIDTH })
        .webp({ quality: 88, alphaQuality: 100 })
        .toFile(join(OUT, `${id}-${side}.webp`));
    }
    console.log(`${id}  aspect: ${width} / ${height}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
