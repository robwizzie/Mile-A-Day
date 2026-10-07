import { ImageResponse } from "next/og";
import {
  BRAND,
  Glow,
  Lockup,
  OG_SIZE,
  StoreLine,
  dashboardDataURI,
  iconDataURI,
  ogFonts,
} from "./_og/shared";

// The site's link preview (iMessage, Slack, X, LinkedIn…), generated at build
// time and reused for Twitter. It mirrors the hero: the same headline in the
// same type, beside the real dashboard. /u/<username> and /p/<id> have their
// own cards.
export const alt =
  "Mile A Day — One mile. Every day. Free on iPhone and Apple Watch.";
export const size = OG_SIZE;
export const contentType = "image/png";

export default async function OpengraphImage() {
  const [fonts, icon, dashboard] = await Promise.all([
    ogFonts(),
    iconDataURI(),
    dashboardDataURI(),
  ]);

  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        position: "relative",
        overflow: "hidden",
        backgroundColor: BRAND.ground,
        fontFamily: "DM Sans",
      }}
    >
      <Glow top={-260} left={620} size={820} alpha={0.34} />
      <Glow top={380} left={-240} size={560} alpha={0.16} />

      {/* Copy */}
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "60px 0 62px 72px",
          width: 760,
        }}
      >
        <Lockup icon={icon} />

        <div style={{ display: "flex", flexDirection: "column" }}>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              fontFamily: "Bebas Neue",
              fontSize: 140,
              lineHeight: 0.88,
              letterSpacing: -1,
            }}
          >
            <div style={{ display: "flex", color: BRAND.ink }}>ONE MILE.</div>
            <div
              style={{
                display: "flex",
                backgroundImage: `linear-gradient(90deg, ${BRAND.red} 0%, ${BRAND.pink} 100%)`,
                backgroundClip: "text",
                color: "transparent",
              }}
            >
              EVERY DAY.
            </div>
          </div>
          <div
            style={{
              display: "flex",
              marginTop: 22,
              fontSize: 32,
              fontWeight: 500,
              lineHeight: 1.3,
              color: BRAND.muted,
              maxWidth: 600,
            }}
          >
            Walk it or run it. Just get it done.
          </div>
        </div>

        <StoreLine />
      </div>

      {/* The real app, tilted like the hero's floating phone. */}
      <div
        style={{
          position: "absolute",
          top: 70,
          left: 818,
          display: "flex",
          padding: 10,
          borderRadius: 54,
          backgroundColor: "#1c1c1e",
          border: "2px solid rgba(255,255,255,0.12)",
          boxShadow:
            "0 40px 90px rgba(0,0,0,0.65), 0 0 120px rgba(199,37,84,0.25)",
          transform: "rotate(6deg)",
        }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={dashboard}
          width={320}
          height={590}
          alt=""
          style={{
            borderRadius: 44,
            objectFit: "cover",
            objectPosition: "top",
          }}
        />
      </div>
    </div>,
    { ...size, fonts },
  );
}
