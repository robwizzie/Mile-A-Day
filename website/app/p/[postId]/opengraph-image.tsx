import { ImageResponse } from "next/og";

// The link unfurl for a shared post (iMessage, Slack, socials): a branded card
// naming the author, with their real avatar and streak.
//
// Deliberately NO route, photo, caption or distance. A post is friends-only
// content and this image travels the open web — a link forwarded out of the
// group chat it was meant for is the normal case, not the edge case — so the
// image follows the page's own signpost rule: confirm the link is real, say
// whose post it is, look like the app. Everything on it is already
// world-readable for that username at `/public/users/:username`.

import {
  getPublicPost,
  publicAuthorInitials,
  publicAuthorName,
  publicAvatarURL,
  publicStreak,
  type PublicPost,
} from "./publicPost";

export const alt = "A Mile A Day post";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const MAD_RED = "#c72554";

/**
 * The avatar, inlined as a data URI.
 *
 * Fetched here rather than handed to Satori as a URL because this image must
 * NEVER fail: an ImageResponse that throws on a slow or missing avatar returns
 * a 500, and a crawler that gets a 500 shows no card at all — strictly worse
 * than the initials fallback. Bounded by a timeout and a size cap for the same
 * reason.
 */
async function avatarDataURI(url: string | null): Promise<string | null> {
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

function avatarBlock(post: PublicPost | null, avatar: string | null) {
  if (avatar) {
    return (
      <img
        src={avatar}
        width={184}
        height={184}
        style={{
          width: 184,
          height: 184,
          borderRadius: 184,
          objectFit: "cover",
          border: `6px solid ${MAD_RED}`,
        }}
      />
    );
  }
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        width: 184,
        height: 184,
        borderRadius: 184,
        backgroundColor: "#252525",
        border: `6px solid ${MAD_RED}`,
        color: "#f5f5f5",
        fontSize: 68,
        fontWeight: 700,
        letterSpacing: 2,
      }}
    >
      {publicAuthorInitials(post)}
    </div>
  );
}

export default async function Image({
  params,
}: {
  params: Promise<{ postId: string }>;
}) {
  const { postId } = await params;
  // `getPublicPost` already swallows failures into null, and every reader below
  // handles null — the unfurl degrades to "A runner", it never 500s.
  const post = await getPublicPost(postId);
  const name = publicAuthorName(post);
  const streak = publicStreak(post);
  const avatar = await avatarDataURI(publicAvatarURL(post));

  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        justifyContent: "space-between",
        padding: 64,
        backgroundImage: "linear-gradient(180deg, #17171f 0%, #050507 100%)",
        position: "relative",
      }}
    >
      {/* Accent glow, same language as the app's art canvas. */}
      <div
        style={{
          position: "absolute",
          top: -220,
          right: -120,
          width: 700,
          height: 700,
          borderRadius: 700,
          backgroundImage:
            "radial-gradient(circle, rgba(199,37,84,0.42) 0%, rgba(199,37,84,0) 70%)",
        }}
      />

      <div
        style={{
          display: "flex",
          alignItems: "center",
          color: "#ffffff",
          fontSize: 32,
          fontWeight: 700,
          letterSpacing: 3,
        }}
      >
        MILE A DAY
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: 40 }}>
        {avatarBlock(post, avatar)}

        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 16,
            maxWidth: 800,
          }}
        >
          <div
            style={{
              display: "flex",
              color: "#ffffff",
              fontSize: 68,
              fontWeight: 800,
            }}
          >
            {name}
          </div>

          {streak !== null ? (
            <div
              style={{
                display: "flex",
                alignItems: "center",
                alignSelf: "flex-start",
                padding: "10px 24px",
                borderRadius: 999,
                backgroundColor: "rgba(199,37,84,0.22)",
                border: `2px solid ${MAD_RED}`,
                color: "#ffffff",
                fontSize: 30,
                fontWeight: 700,
                letterSpacing: 1,
              }}
            >
              {streak} DAY STREAK
            </div>
          ) : null}
        </div>
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        <div
          style={{
            display: "flex",
            color: "#ffffff",
            fontSize: 40,
            fontWeight: 700,
          }}
        >
          shared a post on Mile A Day
        </div>
        <div
          style={{
            display: "flex",
            color: "rgba(255,255,255,0.6)",
            fontSize: 28,
          }}
        >
          Posts are shared with friends — open it in the app to see the run
        </div>
      </div>
    </div>,
    size,
  );
}
