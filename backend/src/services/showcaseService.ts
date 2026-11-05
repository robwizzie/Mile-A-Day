import { PostgresService } from "./DbService.js";
import { signMediaUrl } from "./mediaSigningService.js";

const db = PostgresService.getInstance();

/**
 * Example feed photos for the app's onboarding ("this is what your friends'
 * walks look like"), served to devices that are NOT signed in yet.
 *
 * PUBLIC + UNAUTHENTICATED, so it is an exact allowlist of post ids the owner
 * chose, never a query over the feed. A listed post that was since deleted,
 * pulled off the feed, or whose author is gone simply drops out. Post media is
 * only ever served signed, so the urls here are signed like the feed's.
 *
 * `SHOWCASE_POST_IDS` (comma-separated) overrides the default list without a
 * deploy; an empty value turns the showcase off (the app falls back to drawn
 * sample cards).
 */
export const DEFAULT_SHOWCASE_POST_IDS = [
  "fbc7ab58-46c2-47ec-aead-93ef5ee916ab",
  "ce1bc4df-cc72-472a-ab7c-9ad0ec720c7b",
  "71b38ace-d81d-4d4f-b1a4-2820f6732512",
  "2c2fcbce-c140-4ea2-b925-11d303ba2540",
  "2752cbda-16af-40b9-8468-dcca5cd5c09a",
  "7669ff18-5270-4b93-b65a-be7dd689e005",
];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_PHOTOS = 12;

export function showcasePostIds(env: string | undefined = process.env.SHOWCASE_POST_IDS): string[] {
  if (env === undefined) return DEFAULT_SHOWCASE_POST_IDS;
  return env
    .split(",")
    .map((s) => s.trim())
    .filter((s) => UUID.test(s))
    .slice(0, MAX_PHOTOS);
}

export interface ShowcasePhoto {
  post_id: string;
  /** Signed, server-relative path (same form as feed `media_url`). */
  media_url: string;
  caption: string | null;
  /** Miles, 2 dp; null when the post carried no distance. */
  distance: number | null;
  /** The author's streak on the day of the post. */
  streak: number | null;
  local_date: string;
  username: string;
  profile_image_url: string | null;
}

let cache: { key: string; at: number; photos: ShowcasePhoto[] } | null = null;
const CACHE_MS = 10 * 60 * 1000;

export function clearShowcaseCache() {
  cache = null;
}

export async function getShowcasePhotos(ids: string[] = showcasePostIds()): Promise<ShowcasePhoto[]> {
  if (ids.length === 0) return [];
  const key = ids.join(",");
  if (cache && cache.key === key && Date.now() - cache.at < CACHE_MS) return cache.photos;

  const rows = await db.query<{
    post_id: string;
    media_url: string;
    caption: string | null;
    distance: string | null;
    streak: string | null;
    local_date: string;
    username: string;
    profile_image_url: string | null;
  }>(
    `SELECT p.post_id::text AS post_id, p.media_url, p.caption,
            p.stats_snapshot->>'distance' AS distance,
            p.stats_snapshot->>'streak' AS streak,
            p.local_date::text AS local_date,
            u.username, u.profile_image_url
       FROM unnest($1::uuid[]) WITH ORDINALITY AS l(post_id, ord)
       JOIN posts p ON p.post_id = l.post_id
       JOIN users u ON u.user_id = p.user_id
      WHERE p.deleted_at IS NULL
        AND p.share_to_feed = true
        AND u.username IS NOT NULL
      ORDER BY l.ord`,
    [ids],
  );

  const num = (v: string | null) => {
    const n = v === null ? NaN : Number(v);
    return Number.isFinite(n) ? n : null;
  };
  const photos = rows.map((r) => {
    const d = num(r.distance);
    const s = num(r.streak);
    return {
      post_id: r.post_id,
      media_url: signMediaUrl(r.media_url),
      caption: r.caption,
      distance: d === null ? null : Math.round(d * 100) / 100,
      streak: s === null ? null : Math.round(s),
      local_date: r.local_date,
      username: r.username,
      profile_image_url: r.profile_image_url,
    };
  });
  cache = { key, at: Date.now(), photos };
  return photos;
}
