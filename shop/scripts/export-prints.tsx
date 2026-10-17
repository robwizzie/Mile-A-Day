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

const OUT = join(process.cwd(), "print-files");
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
    "Production prints for the drawn Mile A Day pieces, made by `npm run prints` from `components/designs.tsx`.",
    "Transparent PNGs at **300 DPI**, trimmed to the artwork. Sizes assume a size M (about 20 in wide flat).",
    "",
    "In Tapstitch: **Add new design** → pick the blank → upload each file to its print area → set the width and",
    "position below → **Download mockups** (front and back, flat on white or transparent) and drop them in",
    "`shop/public/garments/` as `<product-id>-front.png` / `-back.png`.",
    "",
  ];

  for (const p of PRODUCTS) {
    if (p.art.kind !== "drawn") continue;
    const parts: ("front" | "back" | "sleeve")[] = ["front", "back", ...(hasSleevePrint(p.art.design) ? (["sleeve"] as const) : [])];
    await mkdir(join(OUT, p.id), { recursive: true });
    guide.push(`## ${p.name} — ${p.colorName} (\`${p.id}\`)`, "", `Blank: ${p.kind}, ${p.colorName.toLowerCase()}.`, "");
    guide.push("| File | Print area | Width | Height | Placement |", "|---|---|---|---|---|");

    for (const part of parts) {
      const markup = renderToStaticMarkup(<PrintOnly design={p.art.design} part={part} />)
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
      }
      guide.push(`| \`${p.id}/${file}\` | ${PLACE[part]} | ${inch(info.width)} in | ${inch(info.height)} in | ${placement} |`);
      console.log(`${p.id}/${file}  ${info.width}×${info.height}`);
    }
    guide.push("");
  }
  await writeFile(join(OUT, "README.md"), guide.join("\n"));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
