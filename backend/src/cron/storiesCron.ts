import cron from "node-cron";
import fs from "fs";
import path from "path";
import { PostgresService } from "../services/DbService.js";
import { runJob } from "./cronRunner.js";

const db = PostgresService.getInstance();

/**
 * Story expiry is enforced at query time (story_expires_at > NOW()) and ONLY
 * affects story surfaces (rail/viewer). The post row and its photo are
 * permanent: the feed and profile grid keep showing the photo forever, and
 * deleting the post is the only way it disappears. So there is deliberately
 * NO expiry-driven soft-delete here — this cron only sweeps orphaned upload
 * files that no live post references.
 */

/**
 * Delete /uploads/posts files older than 72h that NOTHING references —
 * catches orphans from uploads that never completed a POST /posts.
 *
 * Exported for `scripts/orphan-sweep-check.mjs`: which tables count as a
 * reference is the whole correctness of this job, it can only ever be wrong
 * by deleting a file, and it is unobservable until a user reports a blank
 * cover days later. That is not something to verify by reading the query.
 *
 * The reference check deliberately includes SOFT-DELETED posts: deleted_at is
 * the undo path, and a photo is often the only copy the user has. The old
 * live-rows-only check made every soft delete silently irreversible — delete
 * a story (whose photo also fronts the run's feed card), and by the next
 * 3:30 AM sweep the photo file was gone from disk forever.
 */
export async function sweepOrphanedMedia(): Promise<void> {
  const dir = path.join(process.cwd(), "uploads", "posts");
  let files: string[];
  try {
    files = await fs.promises.readdir(dir);
  } catch {
    return; // dir not created yet
  }
  const cutoff = Date.now() - 72 * 60 * 60 * 1000;
  let removed = 0;
  for (const file of files) {
    const full = path.join(dir, file);
    let mtimeMs: number;
    try {
      mtimeMs = (await fs.promises.stat(full)).mtimeMs;
    } catch {
      continue;
    }
    if (mtimeMs > cutoff) continue;
    const mediaUrl = `/uploads/posts/${file}`;
    // Compare against the stored value's PATH — rows written before the
    // query-stripping landed (or through any future gap) may carry a
    // ?e=&s= signature, and an exact-equality check would misread their
    // files as orphans and delete user photos.
    //
    // EVERY table that can own a file in this directory has to be listed
    // here, and two were missing. `uploads/posts/` is not "the posts table's
    // folder" — it is where `uploadPostMedia` puts everything, and three
    // different features point at it:
    //   * posts.media_url                  — the post's own photo
    //   * posts.dual_media_url             — its FRONT & BACK twin (the
    //                                        swapped composition)
    //   * post_highlights.cover_image_url  — a Story Highlight's custom cover
    //   * post_coauthors.media_url         — a crew member's slide on a
    //                                        buddy walk's shared post
    //   * post_coauthors.dual_media_url    — that slide's FRONT & BACK twin
    // The last two were invisible to this query, so 72h after someone set a
    // highlight cover (or added their photo to a friend's buddy walk) this
    // job deleted the file while the row went on pointing at it. The symptom
    // is not an error anywhere: the rail's AsyncImage just draws its empty
    // placeholder, and re-saving the highlight then 400s on the controller's
    // fs.existsSync check with "invalid_cover_image", naming the wrong cause.
    // A missed table here is silent, permanent data loss — add to this list
    // whenever a new feature stores a path under /uploads/posts/.
    const referenced = await db.query<{ exists: boolean }>(
      `SELECT EXISTS (
				SELECT 1 FROM posts WHERE split_part(media_url, '?', 1) = $1
				UNION ALL
				SELECT 1 FROM posts WHERE split_part(dual_media_url, '?', 1) = $1
				UNION ALL
				SELECT 1 FROM post_highlights
				 WHERE split_part(cover_image_url, '?', 1) = $1
				UNION ALL
				SELECT 1 FROM post_coauthors
				 WHERE split_part(media_url, '?', 1) = $1
				UNION ALL
				SELECT 1 FROM post_coauthors
				 WHERE split_part(dual_media_url, '?', 1) = $1
			) AS exists`,
      [mediaUrl],
    );
    if (referenced[0]?.exists) continue;
    await fs.promises.unlink(full).catch(() => {});
    removed += 1;
  }
  if (removed)
    console.log(`[CRON] Swept ${removed} orphaned post media file(s).`);
}

export function startStoriesCron(): void {
  // Daily at 3:30 AM ET: sweep orphaned upload files.
  cron.schedule(
    "30 3 * * *",
    async () => {
      await runJob("media.sweep_orphans", sweepOrphanedMedia);
    },
    { timezone: "America/New_York" },
  );

  console.log("Stories cron scheduled (3:30 AM ET orphan sweep).");
}
