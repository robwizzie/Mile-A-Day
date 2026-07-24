import { ImageResponse } from "next/og";

// Branded social-share card, generated at build time. Used for both OpenGraph
// and Twitter (Next reuses opengraph-image when no twitter-image is present),
// so links to mileaday.run render a real preview instead of a blank card.
export const alt = "Mile A Day — Walk or run a mile every single day";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
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
        <div
          style={{
            display: "flex",
            height: "20px",
            width: "20px",
            borderRadius: "50%",
            backgroundColor: "#c72554",
          }}
        />
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
