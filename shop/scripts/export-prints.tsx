// Exports every drawn design's prints as production files for Tapstitch:
// transparent PNGs at 300 DPI, trimmed to the artwork, plus a placement guide
// (print-files/README.md) giving each print's size and where it sits.
//
//   npm run prints
//
// Sizes come from the design box: the drawn garment is 400 units wide, taken
// as a 20-inch-wide size M flat lay, so 1 unit = 0.05 in = 15 px at 300 DPI.

import { Resvg } from "@resvg/resvg-js";
import { renderToStaticMarkup } from "react-dom/server";
import sharp from "sharp";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { PRODUCTS } from "../lib/catalog";
import { PrintOnly, hasSleevePrint } from "../components/designs";
import { BODIES } from "../lib/garment-bodies";

const OUT = join(process.cwd(), "print-files");
const WEB = join(process.cwd(), "public/prints");
const FONTS = [join(process.cwd(), "scripts/fonts/BebasNeue-Regular.ttf"), join(process.cwd(), "scripts/fonts/DMSans-Medium.ttf")];
const PX_PER_UNIT = 15; // 300 DPI at 20 in per 400 units
const DPI = 300;
const COLLAR_Y = 24; // where the neckline's top sits in the design box

const PLACE: Record<string, string> = {
  front: "Front",
  back: "Back",
  sleeve: "Right sleeve (reads top to bottom, shoulder to cuff)",
};

async function main() {
  await mkdir(OUT, { recursive: true });
  const guide: string[] = [
    "# Print files",
    "",
    "Production prints for the Mile A Day pieces, made by `npm run prints` from `components/designs.tsx`.",
    "Transparent PNGs at **300 DPI**, trimmed to the artwork. Sizes assume a size M (about 20 in wide flat).",
    "",
    "In Tapstitch: **Add new design** → pick the blank → upload each file to its print area → set the width and",
    "position below → **Save Design**. Save the design's front and back mockups (flat on white) to a folder as",
    "`<product-id>-front.png` / `-back.png`, then `npm run cutouts -- <folder>` writes the rack photos to",
    "`shop/public/garments/` and prints each piece's aspect for `lib/catalog.ts`.",
    "",
  ];

  // For the 3D garments: each front/back print as a web texture, and where
  // it sits in inches, written to lib/print-placements.ts.
  await mkdir(WEB, { recursive: true });
  const placements: string[] = [];

  for (const p of PRODUCTS) {
    const design = p.art.design;
    if (!design) continue;
    const parts: ("front" | "back" | "sleeve")[] = ["front", "back", ...(hasSleevePrint(design) ? (["sleeve"] as const) : [])];
    await mkdir(join(OUT, p.id), { recursive: true });
    guide.push(`## ${p.name} — ${p.colorName} (\`${p.id}\`)`, "", `Blank: ${p.kind}, ${p.colorName.toLowerCase()}.`, "");
    guide.push("| File | Print area | Width | Height | Placement |", "|---|---|---|---|---|");

    for (const part of parts) {
      const markup = renderToStaticMarkup(<PrintOnly design={design} part={part} />)
        .replaceAll("var(--font-bebas-neue), Impact, sans-serif", "Bebas Neue")
        .replaceAll("var(--font-dm-sans), sans-serif", "DM Sans");
      const png = new Resvg(markup, {
        fitTo: { mode: "width", value: 400 * PX_PER_UNIT },
        font: { fontFiles: FONTS, loadSystemFonts: false, defaultFontFamily: "Bebas Neue" },
        background: "rgba(0,0,0,0)",
      })
        .render()
        .asPng();
      const { data, info } = await sharp(png).trim({ threshold: 1 }).png().toBuffer({ resolveWithObject: true });
      const file = `${part}.png`;
      await writeFile(join(OUT, p.id, file), data);

      const left = -(info.trimOffsetLeft ?? 0);
      const top = -(info.trimOffsetTop ?? 0);
      const inch = (px: number) => (px / DPI).toFixed(1);
      let placement: string;
      if (part === "sleeve") {
        placement = `centred on the sleeve, starting ${inch(top - 20 * PX_PER_UNIT + 2 * DPI)} in below the shoulder seam`;
      } else {
        const below = top - COLLAR_Y * PX_PER_UNIT;
        // Offset of the print's centre from the garment's centre line, as worn.
        const centre = left + info.width / 2 - 200 * PX_PER_UNIT;
        const side =
          Math.abs(centre) < 0.3 * DPI
            ? "centred"
            : part === "front"
              ? `${inch(Math.abs(centre))} in to the wearer's ${centre > 0 ? "left" : "right"} of centre (left chest)`
              : `${inch(Math.abs(centre))} in ${centre > 0 ? "right" : "left"} of centre`;
        placement = `${side}, top ${inch(below)} in below the collar`;
        const web = `${p.id}-${part}.webp`;
        await sharp(data).resize({ width: 1024, height: 1024, fit: "inside", withoutEnlargement: true }).webp({ quality: 90, alphaQuality: 100 }).toFile(join(WEB, web));
        const n = (px: number) => +(px / DPI).toFixed(2);
        placements.push(
          `  "${p.id}/${part}": { src: "/prints/${web}", width: ${n(info.width)}, height: ${n(info.height)}, right: ${n(centre)}, below: ${n(below)} },`,
        );
      }
      guide.push(`| \`${p.id}/${file}\` | ${PLACE[part]} | ${inch(info.width)} in | ${inch(info.height)} in | ${placement} |`);
      console.log(`${p.id}/${file}  ${info.width}×${info.height}`);
    }
    guide.push("");
  }
  await writeFile(join(OUT, "README.md"), guide.join("\n"));
  // The hoodie predates the drawn designs: its prints are lifted from its photos.
  for (const part of ["front", "back", "sleeve"] as const) placements.push(await photoPrint("extra-mile-hoodie", part));
  await writeFile(
    join(process.cwd(), "lib/print-placements.ts"),
    [
      "// Generated by `npm run prints` — each front/back print's texture and placement,",
      "// in inches on a size M: `right` of the centre line as you look at that side,",
      "// top edge `below` the collar.",
      "",
      "export type Placement = { src: string; width: number; height: number; right: number; below: number };",
      "",
      "export const PLACEMENTS: Record<string, Placement> = {",
      ...placements,
      "};",
      "",
    ].join("\n"),
  );
}

/**
 * Lifts a print off a photo of a dark garment (light ink on black fabric
 * separates by brightness) and places it in the same inches as a drawn
 * design: the torso's width in the photo counts as the 20 in of a size M.
 */
async function photoPrint(id: string, part: "front" | "back" | "sleeve") {
  // The sleeve bolt is read off the front photo's wearer's-left sleeve (it faces the camera most).
  const side = part === "sleeve" ? "front" : part;
  // Where to look (inside the torso, clear of the sleeve prints) and where
  // the collar sits at the centre line, as shares of the photo.
  const WINDOW = { front: [0.36, 0.3, 0.64, 0.66], back: [0.32, 0.38, 0.68, 0.76], sleeve: [0.8, 0.35, 0.97, 0.78] }[part];
  const COLLAR = { front: 0.33, back: 0.29 }[side];
  const [l, r] = BODIES[`/garments/hoodie-front.webp`];
  const { data, info } = await sharp(join(process.cwd(), `public/garments/hoodie-${side}.webp`))
    .flatten({ background: "#000" })
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width: w, height: h, channels } = info;
  const x0 = Math.round(WINDOW[0] * w), y0 = Math.round(WINDOW[1] * h), x1 = Math.round(WINDOW[2] * w), y1 = Math.round(WINDOW[3] * h);
  // Ink: bright on the black fabric; on the sleeve, red (the fabric's folds catch light too).
  const ink = (i: number) => (part === "sleeve" ? Math.max(0, data[i] - Math.max(data[i + 1], data[i + 2])) * 1.4 : Math.max(data[i], data[i + 1], data[i + 2]));
  let top = h, left = w, bottom = 0, right = 0;
  for (let y = y0; y < y1; y++)
    for (let x = x0; x < x1; x++)
      if (ink((y * w + x) * channels) > 90) {
        top = Math.min(top, y); bottom = Math.max(bottom, y);
        left = Math.min(left, x); right = Math.max(right, x);
      }
  const pad = 6;
  left -= pad; top -= pad; right += pad; bottom += pad;
  const cw = right - left + 1, ch = bottom - top + 1;
  const out = Buffer.alloc(cw * ch * 4);
  for (let y = 0; y < ch; y++)
    for (let x = 0; x < cw; x++) {
      const i = ((top + y) * w + left + x) * channels;
      const v = ink(i);
      const a = Math.min(1, Math.max(0, (v - 40) / 60));
      const o = (y * cw + x) * 4;
      // Un-mix the fabric (about rgb 18) out of the edge pixels.
      for (let c = 0; c < 3; c++) out[o + c] = a > 0 ? Math.min(255, Math.max(0, (data[i + c] - 18 * (1 - a)) / a)) : 0;
      out[o + 3] = Math.round(a * 255);
    }
  const web = `${id}-${part}.webp`;
  await sharp(out, { raw: { width: cw, height: ch, channels: 4 } }).webp({ quality: 90, alphaQuality: 100 }).toFile(join(WEB, web));
  const body = (r - l) * w;
  const inches = (px: number) => +((px / body) * 20).toFixed(2);
  return `  "${id}/${part}": { src: "/prints/${web}", width: ${inches(cw)}, height: ${inches(ch)}, right: ${inches(left + cw / 2 - ((l + r) / 2) * w)}, below: ${inches(top - COLLAR * h)} },`;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
