import { ImageResponse } from "next/og";

// The link unfurl for a shared post (iMessage, Slack, socials): a branded
// route-art-styled card naming the author. Deliberately NO real route, photo
// or stats — a post is friends-only content and this image travels the open
// web, so it follows the page's own signpost rule: confirm the link is real,
// say whose post it is, look like the app. The squiggle is decorative.

import { getPublicPost, publicAuthorName } from "./publicPost";

export const alt = "A Mile A Day post";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

async function authorName(postId: string): Promise<string> {
  // Shared resolver — the unfurl must never 500 over a preview fetch, and
  // getPublicPost already swallows failures into null.
  return publicAuthorName(await getPublicPost(postId));
}

export default async function Image({
  params,
}: {
  params: Promise<{ postId: string }>;
}) {
  const { postId } = await params;
  const name = await authorName(postId);

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: 64,
          backgroundImage:
            "linear-gradient(180deg, #17171f 0%, #050507 100%)",
          position: "relative",
        }}
      >
        {/* Accent glow, same language as the app's art canvas. */}
        <div
          style={{
            position: "absolute",
            top: -180,
            left: 300,
            width: 600,
            height: 600,
            borderRadius: 600,
            backgroundImage:
              "radial-gradient(circle, rgba(199,37,84,0.45) 0%, rgba(199,37,84,0) 70%)",
          }}
        />
        {/* Decorative route squiggle — NOT the real route (privacy). */}
        <svg
          width="1200"
          height="630"
          viewBox="0 0 1200 630"
          style={{ position: "absolute", top: 0, left: 0 }}
        >
          <path
            d="M 140 470 C 260 380, 340 520, 470 440 S 660 280, 790 350 S 990 480, 1080 380"
            fill="none"
            stroke="rgba(199,37,84,0.9)"
            strokeWidth="10"
            strokeLinecap="round"
          />
          <circle cx="140" cy="470" r="14" fill="#34c759" />
          <circle cx="1080" cy="380" r="14" fill="#c72554" />
        </svg>

        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 16,
            color: "#ffffff",
            fontSize: 34,
            fontWeight: 700,
            letterSpacing: 2,
          }}
        >
          MILE A DAY
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <div style={{ color: "#ffffff", fontSize: 64, fontWeight: 800 }}>
            {name} got their mile in
          </div>
          <div style={{ color: "rgba(255,255,255,0.65)", fontSize: 32 }}>
            Open in the app to see the run
          </div>
        </div>
      </div>
    ),
    size,
  );
}
