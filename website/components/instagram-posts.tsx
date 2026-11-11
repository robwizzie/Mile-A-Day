import { INSTAGRAM_POSTS, INSTAGRAM_URL, TIKTOK_URL } from "@/lib/story";

/** A post or reel link → its embed URL (null if it isn't one). */
function embedUrl(link: string): string | null {
  const m = link.match(/instagram\.com\/(p|reel|reels|tv)\/([A-Za-z0-9_-]+)/);
  if (!m) return null;
  const kind = m[1] === "reels" ? "reel" : m[1];
  return `https://www.instagram.com/${kind}/${m[2]}/embed/`;
}

/**
 * The Instagram posts in lib/story.ts, embedded with Instagram's own player
 * (an iframe, loaded only as it nears the screen, so nothing from Instagram
 * loads for someone who never scrolls here). With no posts listed it's a
 * plain invitation to follow along.
 */
export function InstagramPosts() {
  const embeds = INSTAGRAM_POSTS.map(embedUrl).filter((u): u is string => !!u);

  return (
    <div>
      {embeds.length > 0 && (
        <div
          className={`grid gap-5 sm:grid-cols-2 ${
            embeds.length >= 3 ? "lg:grid-cols-3" : "mx-auto max-w-4xl"
          }`}
        >
          {embeds.map((src, i) => (
            <div
              key={src}
              data-reveal=""
              style={{ "--d": `${i * 80}ms` } as React.CSSProperties}
              className="overflow-hidden rounded-3xl bg-white"
            >
              <iframe
                src={src}
                title={`Mile A Day on Instagram, post ${i + 1}`}
                loading="lazy"
                className="block aspect-[4/5.9] w-full border-0"
                scrolling="no"
              />
            </div>
          ))}
        </div>
      )}
      <div
        data-reveal=""
        className={`flex flex-col items-start gap-4 rounded-3xl bg-white/[0.05] p-7 sm:flex-row sm:items-center sm:justify-between ${embeds.length ? "mt-8" : ""}`}
      >
        <div>
          <p className="font-heading text-[26px] leading-tight">
            Follow along.
          </p>
          <p className="mt-1 text-[15px] text-white/65">
            Day counts, Flamey&apos;s outfits, and what we&apos;re building
            next.
          </p>
        </div>
        <div className="flex flex-wrap gap-3">
          <a
            href={INSTAGRAM_URL}
            target="_blank"
            rel="noopener noreferrer"
            data-track="story_instagram"
            className="lift rounded-full bg-white px-5 py-3 text-[15px] font-semibold text-[#16090c] hover:bg-white/90"
          >
            @mileadayapp on Instagram
          </a>
          <a
            href={TIKTOK_URL}
            target="_blank"
            rel="noopener noreferrer"
            data-track="story_tiktok"
            className="lift rounded-full bg-white/[0.1] px-5 py-3 text-[15px] font-semibold text-white hover:bg-white/[0.16]"
          >
            TikTok
          </a>
        </div>
      </div>
    </div>
  );
}
