/**
 * Orphan media sweep check — what counts as a reference to an upload.
 *
 * `uploads/posts/` is not the posts table's folder. `uploadPostMedia` is the
 * one upload endpoint, so three features store paths there: a post's own
 * photo, a Story Highlight's custom cover, and a crew member's slide on a
 * buddy walk's shared post. The nightly sweep deletes anything older than 72h
 * that it cannot find a reference for — and it only ever knew about the first
 * one, so a highlight cover and a crew photo were both unlinked three days
 * after they were set while their rows went on pointing at them.
 *
 * Nothing errors when that happens. The highlight rail draws its empty
 * placeholder, the crew slide goes blank, and the next save of that highlight
 * 400s on `invalid_cover_image` — which names the wrong cause. It is silent,
 * permanent loss of a file the user may have no other copy of, which is
 * exactly the shape of bug that must not be verified by reading the SQL.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/orphan-sweep-check.mjs
 */
import fs from "fs";
import path from "path";
import { PostgresService } from "../dist/services/DbService.js";
import { sweepOrphanedMedia } from "../dist/cron/storiesCron.js";

const db = PostgresService.getInstance();
const AUTHOR = "swp-author";
const CREW = "swp-crew";
const ALL = [AUTHOR, CREW];
const DIR = path.join(process.cwd(), "uploads", "posts");
const STALE = new Date(Date.now() - 96 * 60 * 60 * 1000);

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

/** A file already older than the 72h cutoff, so one sweep decides its fate. */
function writeStale(name) {
  const full = path.join(DIR, name);
  fs.writeFileSync(full, "x");
  fs.utimesSync(full, STALE, STALE);
  return `/uploads/posts/${name}`;
}

async function cleanup() {
  await db.query(`DELETE FROM post_highlight_items WHERE highlight_id IN (
      SELECT highlight_id FROM post_highlights WHERE user_id = ANY($1::text[]))`, [ALL]);
  await db.query(`DELETE FROM post_highlights WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM post_coauthors WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
  for (const f of fs.existsSync(DIR) ? fs.readdirSync(DIR) : [])
    if (f.startsWith("swp-")) fs.rmSync(path.join(DIR, f), { force: true });
}

async function main() {
  fs.mkdirSync(DIR, { recursive: true });
  await cleanup();
  for (const id of ALL)
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $5, 'Walker') ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );

  const postPhoto = writeStale("swp-author-post.jpg");
  const cover = writeStale("swp-author-cover.jpg");
  const crewSlide = writeStale("swp-crew-slide.jpg");
  const orphan = writeStale("swp-author-orphan.jpg");

  const postId = (
    await db.query(
      `INSERT INTO posts (user_id, media_url, local_date, share_to_feed)
       VALUES ($1, $2, CURRENT_DATE, TRUE) RETURNING post_id`,
      [AUTHOR, postPhoto],
    )
  )[0].post_id;

  // The cover is stored SIGNED on purpose: rows written before query-stripping
  // landed carry a ?e=&s= signature, and the sweep compares paths for exactly
  // that reason. A cover that only survives when stored bare is still a bug.
  const hl = (
    await db.query(
      `INSERT INTO post_highlights (user_id, title, cover_image_url)
       VALUES ($1, 'Walks', $2) RETURNING highlight_id`,
      [AUTHOR, `${cover}?e=1&s=abc`],
    )
  )[0].highlight_id;
  await db.query(
    `INSERT INTO post_highlight_items (highlight_id, post_id, slide_key, sort_index)
     VALUES ($1, $2, '', 0)`,
    [hl, postId],
  );
  await db.query(
    `INSERT INTO post_coauthors (post_id, user_id, status, media_url)
     VALUES ($1, $2, 'accepted', $3)`,
    [postId, CREW, crewSlide],
  );

  await sweepOrphanedMedia();

  const alive = (p) => fs.existsSync(path.join(process.cwd(), p.replace(/^\//, "")));
  check("a post's own photo survives", alive(postPhoto), true);
  check("a Story Highlight's custom cover survives", alive(cover), true);
  check("a crew member's slide on a buddy walk survives", alive(crewSlide), true);
  check("a genuinely unreferenced upload is still swept", alive(orphan), false);

  await cleanup();
  console.log(
    failures === 0
      ? "orphan-sweep-check: all assertions passed"
      : `orphan-sweep-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
