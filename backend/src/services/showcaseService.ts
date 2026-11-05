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
  // Scenery and group walks, being reviewed for the app's bundled photos.
  // Clients only use the first three entries, so these change nothing on
  // screen.
  "69626d63-32e6-4abd-8210-14d0d9017735",
  "dda862e2-be8a-401b-8997-ab8ed6dfadec",
  "07e8f0b6-7dd5-4bb7-ac64-7fd3f71c35a2",
  "94a23f08-81b8-417d-8993-b6da4ce01e0b",
  "ef2e5160-d0f6-4dfd-9131-949d98a4b53f",
  "4bd8d0e4-5531-4a6c-b071-69f31338eb7c",
  "ec50c477-6a52-4bbc-9620-fb84c1d7c84d",
  "0b9cde98-56fd-4c5a-a44b-e25ac11372a0",
  "81c1895c-3f0d-47ce-9872-321f4e50f4ab",
  "04305ad4-2536-44bf-96d2-1b6fde894ae2",
  "a7390e39-f930-44cb-b329-68a3efdd969e",
  "078adb25-cd7e-4524-bc50-d252cc6a8607",
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
