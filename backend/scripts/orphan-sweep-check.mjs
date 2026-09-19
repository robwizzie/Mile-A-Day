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
import { repairSweptMedia } from "../dist/db/repairSweptMedia.js";

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
  // Extra real post photos: the repair's disk guard needs a few referenced
  // files to resolve before it will believe the volume is mounted.
  const canaries = [1, 2, 3].map((n) => writeStale(`swp-author-canary${n}.jpg`));
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
  for (const c of canaries)
    await db.query(
      `INSERT INTO posts (user_id, media_url, local_date, share_to_feed)
       VALUES ($1, $2, CURRENT_DATE, TRUE)`,
      [AUTHOR, c],
    );

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

  // ── The repair, for rows the sweep already broke ───────────────────────
  // Fixing the sweep cannot bring a deleted file back, and the row goes on
  // pointing at it — which is what the user sees: a badged, empty slide where
  // somebody's photo was, and a blank highlight circle.
  const gone = "/uploads/posts/swp-crew-lost.jpg";
  await db.query(`UPDATE post_coauthors SET media_url = $1, photo_added_at = NOW()
                   WHERE post_id = $2 AND user_id = $3`, [gone, postId, CREW]);
  await db.query(`UPDATE post_highlights SET cover_image_url = $1
                   WHERE highlight_id = $2`, [gone, hl]);

  // THE GUARD FIRST, because it is the half that can destroy data. With the
  // post photos missing too, the disk is wrong rather than the rows — an
  // unmounted volume — and the repair must write NOTHING rather than erase
  // every crew photo and cover in the product.
  const parked = path.join(DIR, "..", "swp-parked");
  fs.mkdirSync(parked, { recursive: true });
  for (const f of fs.readdirSync(DIR).filter((f) => f.startsWith("swp-")))
    fs.renameSync(path.join(DIR, f), path.join(parked, f));
  await repairSweptMedia();
  check(
    "an unmounted volume repairs NOTHING",
    (await db.query(`SELECT media_url FROM post_coauthors WHERE post_id = $1 AND user_id = $2`,
      [postId, CREW]))[0].media_url,
    gone,
  );
  for (const f of fs.readdirSync(parked))
    fs.renameSync(path.join(parked, f), path.join(DIR, f));
  fs.rmSync(parked, { recursive: true, force: true });

  // Dry run FIRST: it must name what it found and change nothing, or the
  // inventory that decides whether a snapshot restore is worth attempting
  // would itself destroy the pointers that restore needs.
  process.env.MEDIA_REPAIR_DRY_RUN = "1";
  await repairSweptMedia();
  delete process.env.MEDIA_REPAIR_DRY_RUN;
  check(
    "a dry run reports but writes NOTHING",
    (await db.query(`SELECT media_url FROM post_coauthors WHERE post_id = $1 AND user_id = $2`,
      [postId, CREW]))[0].media_url,
    gone,
  );
  check(
    "...including the highlight cover",
    (await db.query(`SELECT cover_image_url FROM post_highlights WHERE highlight_id = $1`,
      [hl]))[0].cover_image_url,
    gone,
  );

  await repairSweptMedia();
  check(
    "a crew slide whose file is gone stops claiming a photo",
    (await db.query(`SELECT media_url FROM post_coauthors WHERE post_id = $1 AND user_id = $2`,
      [postId, CREW]))[0].media_url,
    null,
  );
  check(
    "...so that participant is offered their photo again",
    (await db.query(`SELECT photo_added_at FROM post_coauthors WHERE post_id = $1 AND user_id = $2`,
      [postId, CREW]))[0].photo_added_at,
    null,
  );
  check(
    "a highlight cover whose file is gone falls back to a member photo",
    (await db.query(`SELECT cover_image_url FROM post_highlights WHERE highlight_id = $1`,
      [hl]))[0].cover_image_url,
    null,
  );
  check(
    "a photo that IS on disk is left alone",
    (await db.query(`SELECT media_url FROM posts WHERE post_id = $1`, [postId]))[0].media_url,
    postPhoto,
  );

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
