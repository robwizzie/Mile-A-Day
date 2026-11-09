/**
 * Comment sticker check — sticker comments (`sticker_id`, commentStickers.ts).
 *
 * A sticker comment must stay readable everywhere that only knows text:
 * shipped apps, the push body, admin tools. Pinned:
 *   - a sticker comment stores its id AND the stand-in text as `content`
 *   - the thread (listComments) and the feed preview (commentPreviewSql)
 *     serve `sticker_id`; a text comment serves null
 *   - the allowlist rejects unknown ids
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/comment-sticker-check.mjs
 */
import crypto from "node:crypto";
import { PostgresService } from "../dist/services/DbService.js";
import { addComment, listComments } from "../dist/services/commentService.js";
import { commentPreviewSql } from "../dist/services/posts/postSql.js";
import {
  isCommentSticker,
  stickerFallbackText,
} from "../dist/services/commentStickers.js";

const db = PostgresService.getInstance();
const USER = "cs-ann";

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label} → ${a}${ok ? "" : ` (expected ${e})`}`);
}

async function cleanup() {
  await db.query(`DELETE FROM post_comments WHERE user_id = $1`, [USER]);
  await db.query(`DELETE FROM posts WHERE user_id = $1`, [USER]);
  await db.query(`DELETE FROM users WHERE user_id = $1`, [USER]);
}

try {
  await cleanup();
  await db.query(
    `INSERT INTO users (user_id, username, apple_sub, email) VALUES ($1::text, $1::text, $1::text, $1::text || '@example.com')`,
    [USER],
  );
  const postId = crypto.randomUUID();
  await db.query(
    `INSERT INTO posts (post_id, user_id, media_url, local_date, share_to_feed)
     VALUES ($1::uuid, $2, $3, CURRENT_DATE, true)`,
    [postId, USER, `/uploads/posts/${postId}.jpg`],
  );

  check("known sticker accepted", isCommentSticker("lets-gooo"), true);
  check("unknown sticker rejected", isCommentSticker("nope"), false);
  check("prototype keys rejected", isCommentSticker("toString"), false);
  check("non-string rejected", isCommentSticker(42), false);
  check("stand-in text", stickerFallbackText("lets-gooo"), "🔥 LET'S GOOO");

  const text = await addComment(USER, postId, "nice one", null);
  const sticker = await addComment(USER, postId, stickerFallbackText("bruh"), null, "bruh");
  check("text comment has no sticker", text?.sticker_id, null);
  check("sticker comment returns its id", sticker?.sticker_id, "bruh");
  check("sticker comment stores the stand-in text", sticker?.content, "🔥 bruh");

  const thread = await listComments(USER, postId);
  check(
    "thread serves sticker_id",
    (thread ?? []).map((c) => [c.content, c.sticker_id]),
    [["nice one", null], ["🔥 bruh", "bruh"]],
  );

  const preview = await db.query(
    `SELECT ${commentPreviewSql("cp.post_id = p.post_id")} AS prev FROM posts p WHERE p.post_id = $2`,
    [USER, postId],
  );
  check(
    "feed preview serves sticker_id",
    (preview[0]?.prev ?? []).map((c) => c.sticker_id),
    [null, "bruh"],
  );
} finally {
  await cleanup();
}

console.log(failures ? `comment-sticker-check: ${failures} FAILED` : "comment-sticker-check: all assertions passed");
process.exit(failures ? 1 : 0);
