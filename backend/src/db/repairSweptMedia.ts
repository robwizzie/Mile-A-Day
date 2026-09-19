import { Client } from "pg";
import fs from "fs";
import path from "path";

/**
 * One-time repair of rows left pointing at media the orphan sweep deleted.
 *
 * `sweepOrphanedMedia` (storiesCron) unlinks anything under /uploads/posts
 * older than 72h that it cannot find a reference for, and until the fix that
 * shipped alongside this file it only recognised `posts.media_url`. But
 * `uploadPostMedia` is the ONE upload endpoint, so two other features store
 * paths in that directory — a Story Highlight's custom cover
 * (`post_highlights.cover_image_url`) and a crew member's slide on a buddy
 * walk's shared post (`post_coauthors.media_url`) — and both were deleted
 * three days after they were set.
 *
 * Fixing the sweep stops new losses. It cannot bring the files back, and the
 * rows still point at them, which is what the user actually sees: a highlight
 * whose circle is blank, and a buddy walk card with a badged, empty slide
 * where somebody's photo used to be. A slide that renders as a broken frame
 * reads as the app losing the picture on purpose; a slide that isn't there
 * reads as a photo never added — which is now the truth, and which also
 * re-offers "add your photo" (`my_photo_added` keys on `media_url`).
 *
 * So this clears ONLY references whose file is genuinely gone.
 *
 * The danger, and the guard
 * -------------------------
 * The catastrophic failure here is the uploads volume not being mounted: every
 * file then looks missing and this would erase every crew photo and cover in
 * the product, including the ones still sitting safely on the real disk. So it
 * never trusts `existsSync` on its own. `posts.media_url` files are the canary
 * — the sweep always recognised them, so on a healthy disk essentially all of
 * them are present. If a meaningful share of THOSE are missing, the disk is
 * wrong rather than the rows, and this aborts having written nothing.
 *
 * Idempotent and cheap on every later boot: once the swept rows are cleared
 * there is nothing left whose file is missing, so it stats a bounded set and
 * writes nothing. `MEDIA_REPAIR_DISABLED=1` turns it off entirely.
 *
 * Every reference it clears is LOGGED with its path first. Clearing the column
 * is what makes the card read honestly, but it also discards the only record
 * of which file belonged to which slide — so if the uploads volume is ever
 * restored from a snapshot, that log is what the files can be matched back
 * against. Set the kill switch before the first deploy if a restore is being
 * attempted, and let this run once the recovery is settled.
 */

/** Sampled from posts.media_url — never swept, so a proxy for "disk is here". */
const CANARY_SAMPLE = 200;
/**
 * How many sampled post photos must resolve before this will write anything.
 *
 * A COUNT, not a ratio, because the failure mode being guarded against is
 * all-or-nothing: a volume is mounted or it is not, and when it is not, ZERO
 * referenced files resolve. A ratio would additionally block the repair on any
 * database with untidy history — old rows whose files predate a storage move,
 * seeded rows that never had a file — which is the common case and precisely
 * when the repair is wanted. A handful of resolving files is proof the right
 * disk is attached; that is all this needs to establish.
 */
const CANARY_MIN_PRESENT = 3;

function fileExists(mediaUrl: string): boolean {
  const bare = mediaUrl.split("?")[0];
  if (!bare.startsWith("/uploads/posts/") || bare.includes("..")) return false;
  return fs.existsSync(path.join(process.cwd(), bare.replace(/^\//, "")));
}

/**
 * Is the uploads directory the one these rows were written against?
 *
 * Returns false to mean "don't touch anything" for every uncertain case — no
 * directory, no canaries to judge by, or too many of them missing.
 */
async function diskLooksHealthy(client: Client): Promise<boolean> {
  const dir = path.join(process.cwd(), "uploads", "posts");
  if (!fs.existsSync(dir)) {
    console.log("[media-repair] uploads/posts missing — skipping.");
    return false;
  }
  const { rows } = await client.query<{ media_url: string }>(
    `SELECT media_url FROM posts
      WHERE media_url IS NOT NULL AND media_url LIKE '/uploads/posts/%'
        AND deleted_at IS NULL
      ORDER BY created_at DESC
      LIMIT $1`,
    [CANARY_SAMPLE],
  );
  if (rows.length === 0) {
    console.log("[media-repair] no post photos to judge the disk by — skipping.");
    return false;
  }
  const present = rows.filter((r) => fileExists(r.media_url)).length;
  // With fewer rows than the floor, every one of them has to resolve — a
  // brand-new install shouldn't be able to pass the guard by having nothing.
  const needed = Math.min(CANARY_MIN_PRESENT, rows.length);
  if (present < needed) {
    console.warn(
      `[media-repair] only ${present}/${rows.length} sampled post photos found ` +
        "on disk — treating this as a volume problem, not missing rows. " +
        "Nothing changed.",
    );
    return false;
  }
  return true;
}

export async function repairSweptMedia(): Promise<void> {
  if (process.env.MEDIA_REPAIR_DISABLED === "1") return;

  // A dedicated connection for the same reason backfillFeedRoles takes one:
  // the shared pool's 30s timeouts are right for requests and wrong for a
  // maintenance pass that stats files.
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    statement_timeout: 0,
    query_timeout: 0,
  });

  try {
    await client.connect();
    if (!(await diskLooksHealthy(client))) return;

    let clearedSlides = 0;
    const slides = await client.query<{
      post_id: string;
      user_id: string;
      media_url: string;
    }>(
      `SELECT post_id, user_id, media_url FROM post_coauthors
        WHERE media_url IS NOT NULL AND media_url <> ''`,
    );
    for (const row of slides.rows) {
      if (fileExists(row.media_url)) continue;
      // photo_added_at goes with it: it is the timestamp OF the photo being
      // cleared, and leaving it behind describes a slide that isn't there.
      // The caption stays — those are their words, not the picture.
      // Printed BEFORE the write, one line per reference, because this log is
      // the only remaining record of which file each row pointed at. The file
      // is already gone; the path is what a restore from a volume snapshot has
      // to be matched back against, and nulling the column without recording
      // it first would turn a recoverable loss into a permanent one.
      console.log(
        `[media-repair] crew slide post=${row.post_id} user=${row.user_id} ` +
          `lost=${row.media_url}`,
      );
      await client.query(
        `UPDATE post_coauthors SET media_url = NULL, photo_added_at = NULL
          WHERE post_id = $1 AND user_id = $2`,
        [row.post_id, row.user_id],
      );
      clearedSlides += 1;
    }

    let clearedCovers = 0;
    const covers = await client.query<{
      highlight_id: string;
      cover_image_url: string;
    }>(
      `SELECT highlight_id, cover_image_url FROM post_highlights
        WHERE cover_image_url IS NOT NULL AND cover_image_url <> ''`,
    );
    for (const row of covers.rows) {
      if (fileExists(row.cover_image_url)) continue;
      // Clearing it is exactly what the editor's "use a photo from inside"
      // does, so the rail falls back to a member's photo instead of a blank
      // circle — and the highlight keeps working while they re-pick a cover.
      console.log(
        `[media-repair] highlight cover highlight=${row.highlight_id} ` +
          `lost=${row.cover_image_url}`,
      );
      await client.query(
        `UPDATE post_highlights SET cover_image_url = NULL, updated_at = NOW()
          WHERE highlight_id = $1`,
        [row.highlight_id],
      );
      clearedCovers += 1;
    }

    if (clearedSlides || clearedCovers)
      console.log(
        `[media-repair] cleared ${clearedSlides} crew slide(s) and ` +
          `${clearedCovers} highlight cover(s) whose files were swept.`,
      );
  } catch (error: any) {
    // Never fail a boot over this: the rows are already wrong, and a retry
    // next boot is free.
    console.error("[media-repair] skipped:", error?.message ?? error);
  } finally {
    await client.end().catch(() => {});
  }
}
