import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

// Branded social-share card for mileaday.run, generated at build time. Used
// for both OpenGraph and Twitter (Next reuses opengraph-image when there's no
// twitter-image). /p/<id> has its own; /u/<username> inherits this one.
export const alt = "Mile A Day — Walk or run a mile every single day";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpengraphImage() {
  const icon = await readFile(
    join(process.cwd(), "public/images/mad-circle-icon.png"),
  );
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    <div
      style={{
        height: "100%",
        width: "100%",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        backgroundColor: "#0a0a0a",
        backgroundImage:
          "radial-gradient(circle at 78% 22%, rgba(199,37,84,0.28) 0%, rgba(10,10,10,0) 55%)",
        padding: "90px",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "18px",
          fontSize: 30,
          fontWeight: 700,
          letterSpacing: "4px",
          color: "#c72554",
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={iconSrc} width={64} height={64} alt="" />
        MILE A DAY
      </div>

      <div
        style={{
          display: "flex",
          flexDirection: "column",
          marginTop: "36px",
          fontSize: 122,
          fontWeight: 800,
          lineHeight: 1,
          letterSpacing: "-3px",
        }}
      >
        <div style={{ display: "flex", color: "#f5f5f5" }}>ONE MILE.</div>
        <div style={{ display: "flex", color: "#c72554" }}>EVERY DAY.</div>
      </div>

      <div
        style={{
          display: "flex",
          marginTop: "48px",
          fontSize: 40,
          color: "#a0a0a0",
        }}
      >
        Track your streak. Compete with friends.
      </div>

      <div
        style={{
          display: "flex",
          marginTop: "20px",
          fontSize: 28,
          fontWeight: 600,
          letterSpacing: "1px",
          color: "#f5f5f5",
        }}
      >
        Free on iOS &amp; Apple Watch
      </div>
    </div>,
    { ...size },
  );
}
