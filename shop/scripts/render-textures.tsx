// Renders every drawn piece's front and back print to a transparent WebP in
// public/garments/, the textures the 3D garments wear. Run after changing a
// design in components/designs.tsx:
//
//   npm run textures
//
// resvg draws the same SVG the CSS fallback shows, with the fonts loaded from
// scripts/fonts (TTF copies of the site's vendored WOFFs).

import { Resvg } from "@resvg/resvg-js";
import { renderToStaticMarkup } from "react-dom/server";
import sharp from "sharp";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { PRODUCTS } from "../lib/catalog";
import { DrawnGarment } from "../components/designs";

const OUT = join(process.cwd(), "public/garments");
const FONTS = [join(process.cwd(), "scripts/fonts/BebasNeue-Regular.ttf"), join(process.cwd(), "scripts/fonts/DMSans-Medium.ttf")];
const WIDTH = 800; // the 400×440 design box at 2×

async function main() {
  await mkdir(OUT, { recursive: true });
  for (const p of PRODUCTS) {
    if (p.art.kind !== "drawn") continue;
    for (const side of ["front", "back"] as const) {
      const markup = renderToStaticMarkup(
        <DrawnGarment cut={p.art.cut} color={p.art.color} design={p.art.design} side={side} texture />,
      )
        // The page resolves these through next/font CSS variables; resvg
        // needs the real family names.
        .replaceAll("var(--font-bebas-neue), Impact, sans-serif", "Bebas Neue")
        .replaceAll("var(--font-dm-sans), sans-serif", "DM Sans");
      const png = new Resvg(markup, {
        fitTo: { mode: "width", value: WIDTH },
        font: { fontFiles: FONTS, loadSystemFonts: false, defaultFontFamily: "Bebas Neue" },
        background: "rgba(0,0,0,0)",
      })
        .render()
        .asPng();
      const file = join(OUT, `${p.id}-${side}.webp`);
      await sharp(png).webp({ quality: 88, alphaQuality: 100 }).toFile(file);
      console.log(file);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
