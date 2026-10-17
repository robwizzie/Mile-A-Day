import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

// The link-preview card for mileaday.shop: the real hoodie, front and back,
// on the shop's studio ground. Fonts are vendored .woff (Satori can't read
// woff2 or next/font) and the garments PNG (it can't read WebP).

export const alt = "The Go The Extra Mile hoodie, front and back, from the Mile A Day Shop";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const dir = join(process.cwd(), "app/_og");
const dataURI = async (name: string) => `data:image/png;base64,${(await readFile(join(dir, name))).toString("base64")}`;

export default async function Image() {
  const [bebas, dm, front, back] = await Promise.all([
    readFile(join(dir, "fonts/BebasNeue-400.woff")),
    readFile(join(dir, "fonts/DMSans-500.woff")),
    dataURI("hoodie-front.png"),
    dataURI("hoodie-back.png"),
  ]);

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          background: "#f1ede6",
          backgroundImage: "radial-gradient(rgba(20,18,16,0.13) 1.5px, transparent 1.5px)",
          backgroundSize: "26px 26px",
          position: "relative",
        }}
      >
        <div style={{ position: "absolute", left: 60, right: 60, top: 70, height: 12, borderRadius: 6, background: "linear-gradient(180deg,#fdfdfd,#a9a9a9 55%,#d6d6d6)" }} />
        <div style={{ display: "flex", flexDirection: "column", justifyContent: "flex-end", padding: "0 0 64px 72px", width: 520 }}>
          <div style={{ fontFamily: "DM Sans", fontSize: 24, letterSpacing: 6, color: "#6b655d" }}>MILEADAY.SHOP</div>
          <div style={{ fontFamily: "Bebas Neue", fontSize: 112, lineHeight: 0.9, color: "#141210", marginTop: 14, display: "flex", flexDirection: "column" }}>
            <span>GO THE</span>
            <span style={{ color: "#c72554" }}>EXTRA MILE</span>
          </div>
          <div style={{ fontFamily: "DM Sans", fontSize: 26, color: "#6b655d", marginTop: 18 }}>Official Mile A Day merch. Drop 01.</div>
        </div>
        <img src={back} width={360} height={298} style={{ position: "absolute", right: 300, top: 150, opacity: 0.95 }} />
        <img src={front} width={430} height={355} style={{ position: "absolute", right: 40, top: 200 }} />
      </div>
    ),
    {
      ...size,
      fonts: [
        { name: "Bebas Neue", data: bebas, weight: 400, style: "normal" },
        { name: "DM Sans", data: dm, weight: 500, style: "normal" },
      ],
    },
  );
}
