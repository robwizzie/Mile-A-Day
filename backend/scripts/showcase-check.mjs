/**
 * Showcase check — `/public/showcase` (onboarding's example feed photos).
 *
 * The endpoint is UNAUTHENTICATED and hands out signed post-photo urls, so it
 * must only ever serve the exact posts on the allowlist, in that order, and
 * drop any of them the moment the post is deleted or pulled off the feed.
 * Pinned:
 *   - allowlist order is kept; an unknown id is ignored
 *   - deleted / share_to_feed = false posts drop out
 *   - media urls come back signed (`?e=…&s=…`), distance rounded to 2 dp
 *   - SHOWCASE_POST_IDS parsing: junk dropped, empty = showcase off
 *   - only the documented keys ride along (no user_id, email, workout ids)
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/showcase-check.mjs
 */
import crypto from "node:crypto";
import { PostgresService } from "../dist/services/DbService.js";
import {
  getShowcasePhotos,
  showcasePostIds,
  clearShowcaseCache,
  DEFAULT_SHOWCASE_POST_IDS,
} from "../dist/services/showcaseService.js";

const db = PostgresService.getInstance();
const USER = "sc-ann";

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

async function cleanup() {
  await db.query(`DELETE FROM posts WHERE user_id = $1`, [USER]);
  await db.query(`DELETE FROM users WHERE user_id = $1`, [USER]);
}

async function post(opts = {}) {
  const id = crypto.randomUUID();
  await db.query(
    `INSERT INTO posts (post_id, user_id, media_url, caption, stats_snapshot, local_date,
                        share_to_feed, deleted_at)
     VALUES ($1::uuid, $2, $3, $4, $5::jsonb, CURRENT_DATE - 1, $6, $7)`,
    [
      id,
      USER,
      `/uploads/posts/${id}.jpg`,
      opts.caption ?? null,
      JSON.stringify({ distance: opts.distance ?? 1.0194532922, streak: 531 }),
      opts.feed ?? true,
      opts.deleted ? new Date() : null,
    ],
  );
  return id;
}

try {
  await cleanup();
  await db.query(
    `INSERT INTO users (user_id, username, apple_sub, email) VALUES ($1::text, $1::text, $1::text, $1::text || '@example.com')`,
    [USER],
  );
  const a = await post({ caption: "first" });
  const b = await post({ caption: "second", distance: 1.911222 });
  const gone = await post({ deleted: true });
  const hidden = await post({ feed: false });
  const unknown = crypto.randomUUID();

  clearShowcaseCache();
  const photos = await getShowcasePhotos([b, gone, unknown, hidden, a]);
  check("allowlist order kept, deleted/hidden/unknown dropped", photos.map((p) => p.post_id), [b, a]);
  check("distance rounded to 2 dp", photos.map((p) => p.distance), [1.91, 1.02]);
  check("streak served", photos[0]?.streak, 531);
  check("username served", photos[0]?.username, USER);
  check(
    "media urls signed",
    photos.every((p) => /^\/uploads\/posts\/[0-9a-f-]+\.jpg\?e=\d+&s=[0-9a-f]{32}$/.test(p.media_url)),
    true,
  );
  check(
    "only documented keys",
    Object.keys(photos[0] ?? {}).sort(),
    ["caption", "distance", "local_date", "media_url", "post_id", "profile_image_url", "streak", "username"],
  );

  check("env unset → default list", showcasePostIds(undefined), DEFAULT_SHOWCASE_POST_IDS);
  check("env empty → off", showcasePostIds(""), []);
  check("env junk dropped", showcasePostIds(` ${a} , nope, ${b}'; drop table posts;--`), [a]);
  check("empty list → no photos", await getShowcasePhotos([]), []);
} finally {
  await cleanup();
}

console.log(failures ? `showcase-check: ${failures} FAILED` : "showcase-check: all assertions passed");
process.exit(failures ? 1 : 0);
