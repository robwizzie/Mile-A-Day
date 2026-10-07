import { readFile } from "node:fs/promises";
import { join } from "node:path";

// Everything the link-preview cards (opengraph-image.tsx files) share, so the
// home, profile and post unfurls read as one brand: the site's own type (Bebas
// Neue headings, DM Sans body — vendored as .woff because Satori can't read
// woff2 or reach next/font), the app icon, and the colours from globals.css.
//
// `_og` is a private folder: the leading underscore keeps it out of routing.

export const OG_SIZE = { width: 1200, height: 630 };

export const BRAND = {
  red: "#c72554",
  pink: "#ff4d7d",
  ink: "#f5f5f5",
  muted: "#a0a0a0",
  ground: "#0a0a0a",
};

const dir = join(process.cwd(), "app/_og");

export async function ogFonts() {
  const [bebas, dm500, dm700] = await Promise.all([
    readFile(join(dir, "fonts/BebasNeue-400.woff")),
    readFile(join(dir, "fonts/DMSans-500.woff")),
    readFile(join(dir, "fonts/DMSans-700.woff")),
  ]);
  return [
    {
      name: "Bebas Neue",
      data: bebas,
      weight: 400 as const,
      style: "normal" as const,
    },
    {
      name: "DM Sans",
      data: dm500,
      weight: 500 as const,
      style: "normal" as const,
    },
    {
      name: "DM Sans",
      data: dm700,
      weight: 700 as const,
      style: "normal" as const,
    },
  ];
}

async function fileDataURI(name: string, type: string): Promise<string> {
  const bytes = await readFile(join(dir, name));
  return `data:${type};base64,${bytes.toString("base64")}`;
}

export const iconDataURI = () => fileDataURI("icon.png", "image/png");
/** The top of the dashboard screenshot (streak + today's progress), pre-cropped. */
export const dashboardDataURI = () =>
  fileDataURI("dashboard.jpg", "image/jpeg");

/**
 * A remote image (an avatar) inlined as a data URI. Never throws: an
 * ImageResponse that fails on a slow or missing picture returns a 500, and a
 * crawler that gets a 500 shows no card at all — strictly worse than the
 * initials fallback. Bounded by a timeout and a size cap for the same reason.
 */
export async function remoteImageDataURI(
  url: string | null,
): Promise<string | null> {
  if (!url) return null;
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 2500);
    const res = await fetch(url, {
      signal: controller.signal,
      next: { revalidate: 3600 },
    });
    clearTimeout(timeout);
    if (!res.ok) return null;
    const type = res.headers.get("content-type") ?? "";
    if (!type.startsWith("image/")) return null;
    const bytes = await res.arrayBuffer();
    if (bytes.byteLength === 0 || bytes.byteLength > 2_000_000) return null;
    return `data:${type};base64,${Buffer.from(bytes).toString("base64")}`;
  } catch {
    return null;
  }
}

/** The red glow the site's hero sits in (`.hero-gradient`). */
export function Glow({
  top,
  left,
  size,
  alpha,
}: {
  top: number;
  left: number;
  size: number;
  alpha: number;
}) {
  return (
    <div
      style={{
        position: "absolute",
        top,
        left,
        width: size,
        height: size,
        borderRadius: size,
        backgroundImage: `radial-gradient(circle, rgba(199,37,84,${alpha}) 0%, rgba(199,37,84,0) 70%)`,
      }}
    />
  );
}

/** Icon + wordmark, top-left on every card. */
export function Lockup({ icon }: { icon: string }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={icon} width={60} height={60} alt="" />
      <div
        style={{
          display: "flex",
          fontFamily: "Bebas Neue",
          fontSize: 44,
          letterSpacing: 3,
          color: BRAND.ink,
          paddingTop: 6,
        }}
      >
        MILE A DAY
      </div>
    </div>
  );
}

/** The App Store line every card closes on. */
export function StoreLine({
  text = "Free on iPhone & Apple Watch",
}: {
  text?: string;
}) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        alignSelf: "flex-start",
        gap: 12,
        padding: "12px 24px",
        borderRadius: 999,
        backgroundColor: "rgba(199,37,84,0.14)",
        border: "2px solid rgba(199,37,84,0.55)",
        fontFamily: "DM Sans",
        fontWeight: 700,
        fontSize: 26,
        color: BRAND.ink,
      }}
    >
      <svg width="24" height="24" viewBox="0 0 24 24" fill={BRAND.ink}>
        <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
      </svg>
      {text}
    </div>
  );
}

function FlameGlyph({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="#fb923c">
      <path d="M12 2c.6 3.2-1.1 5.1-2.6 6.8C7.9 10.4 6.5 12 6.5 14.6 6.5 18.2 9 21 12 21s5.5-2.8 5.5-6.4c0-2.3-1-4.1-2.2-5.6-.3 1.5-1 2.6-2.1 3.1.4-3.6-.4-7.3-1.2-10.1Z" />
    </svg>
  );
}

/**
 * The card for a link about ONE person — a profile, or a post (which shows
 * only its author: a post is friends-only and an unfurl travels the open web).
 * Everything drawn is world-readable at `/public/users/:username`.
 */
export function PersonCard({
  icon,
  avatar,
  initials,
  name,
  handle,
  streak,
  headline,
  footnote,
}: {
  icon: string;
  avatar: string | null;
  initials: string;
  name: string;
  handle: string | null;
  streak: number | null;
  headline: string;
  footnote: string;
}) {
  const nameSize = name.length > 18 ? 76 : name.length > 12 ? 96 : 116;
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        justifyContent: "space-between",
        padding: "60px 72px 62px",
        position: "relative",
        overflow: "hidden",
        backgroundColor: BRAND.ground,
        fontFamily: "DM Sans",
      }}
    >
      <Glow top={-300} left={640} size={860} alpha={0.32} />
      <Glow top={360} left={-260} size={560} alpha={0.14} />

      <Lockup icon={icon} />

      <div style={{ display: "flex", alignItems: "center", gap: 48 }}>
        {avatar ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={avatar}
            width={216}
            height={216}
            alt=""
            style={{
              width: 216,
              height: 216,
              borderRadius: 216,
              objectFit: "cover",
              border: `7px solid ${BRAND.red}`,
              boxShadow: "0 0 80px rgba(199,37,84,0.45)",
            }}
          />
        ) : (
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              width: 216,
              height: 216,
              borderRadius: 216,
              backgroundColor: "#252525",
              border: `7px solid ${BRAND.red}`,
              boxShadow: "0 0 80px rgba(199,37,84,0.45)",
              fontFamily: "Bebas Neue",
              fontSize: 96,
              color: BRAND.ink,
              paddingTop: 10,
            }}
          >
            {initials}
          </div>
        )}

        <div style={{ display: "flex", flexDirection: "column", maxWidth: 790 }}>
          <div
            style={{
              display: "flex",
              fontFamily: "Bebas Neue",
              fontSize: nameSize,
              lineHeight: 0.95,
              color: BRAND.ink,
              letterSpacing: 1,
            }}
          >
            {name}
          </div>
          {handle ? (
            <div
              style={{
                display: "flex",
                marginTop: 6,
                fontSize: 34,
                fontWeight: 500,
                color: BRAND.muted,
              }}
            >
              {handle}
            </div>
          ) : null}
          {streak !== null ? (
            <div
              style={{
                display: "flex",
                alignItems: "center",
                alignSelf: "flex-start",
                gap: 10,
                marginTop: 22,
                padding: "10px 22px 10px 16px",
                borderRadius: 999,
                backgroundColor: "rgba(199,37,84,0.2)",
                fontSize: 30,
                fontWeight: 700,
                color: BRAND.ink,
              }}
            >
              <FlameGlyph size={30} />
              {streak.toLocaleString("en-US")} day streak
            </div>
          ) : null}
        </div>
      </div>

      <div
        style={{
          display: "flex",
          alignItems: "flex-end",
          justifyContent: "space-between",
          gap: 32,
        }}
      >
        <div style={{ display: "flex", flexDirection: "column", gap: 6, maxWidth: 780 }}>
          <div style={{ display: "flex", fontSize: 34, fontWeight: 700, color: BRAND.ink }}>
            {headline}
          </div>
          <div style={{ display: "flex", fontSize: 25, fontWeight: 500, color: BRAND.muted }}>
            {footnote}
          </div>
        </div>
        <StoreLine text="Get Mile A Day" />
      </div>
    </div>
  );
}
