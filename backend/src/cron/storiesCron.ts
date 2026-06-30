import cron from "node-cron";
import fs from "fs";
import path from "path";
import { PostgresService } from "../services/DbService.js";

const db = PostgresService.getInstance();

/**
 * Expiry is enforced at query time (story_expires_at > NOW()), so this cron is
 * pure hygiene: it soft-deletes expired story-only posts and unlinks their
 * media to bound disk growth. Posts also shared to the feed are KEPT (the feed
 * is permanent), so their media is never touched here. Also sweeps orphaned
 * /uploads/posts files older than a day that no live post references.
 */
async function cleanupExpiredStories(): Promise<void> {
  // Story-only posts whose 24h window has passed: collect their media, then
  // soft-delete. Feed-shared posts are excluded so their photo survives.
  const expired = await db.query<{ post_id: string; media_url: string }>(
    `UPDATE posts
		 SET deleted_at = NOW()
		 WHERE share_to_story
			 AND NOT share_to_feed
			 AND deleted_at IS NULL
			 AND story_expires_at <= NOW()
		 RETURNING post_id, media_url`,
  );

  for (const row of expired) {
    await unlinkMediaIfUnreferenced(row.media_url);
  }
  if (expired.length) {
    console.log(`[CRON] Expired ${expired.length} story-only post(s).`);
  }
}

/**
 * Remove a media file from disk only if no live (non-deleted) post still points
 * at it — a single photo can back both a story and a feed post (shared upload),
 * though the composer currently uploads per-post.
 */
async function unlinkMediaIfUnreferenced(mediaUrl: string): Promise<void> {
  if (!mediaUrl || !mediaUrl.startsWith("/uploads/posts/")) return;
  const stillUsed = await db.query<{ exists: boolean }>(
    `SELECT EXISTS (
			SELECT 1 FROM posts WHERE media_url = $1 AND deleted_at IS NULL
		) AS exists`,
    [mediaUrl],
  );
  if (stillUsed[0]?.exists) return;
  const onDisk = path.join(process.cwd(), mediaUrl.replace(/^\//, ""));
  fs.promises.unlink(onDisk).catch(() => {
    /* already gone */
  });
}

/**
 * Delete /uploads/posts files older than 24h that no live post references —
 * catches orphans from uploads that never completed a POST /posts.
 */
async function sweepOrphanedMedia(): Promise<void> {
  const dir = path.join(process.cwd(), "uploads", "posts");
  let files: string[];
  try {
    files = await fs.promises.readdir(dir);
  } catch {
    return; // dir not created yet
  }
  const cutoff = Date.now() - 24 * 60 * 60 * 1000;
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
    const referenced = await db.query<{ exists: boolean }>(
      `SELECT EXISTS (SELECT 1 FROM posts WHERE media_url = $1 AND deleted_at IS NULL) AS exists`,
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
  // Hourly: expire stories promptly (so disk/privacy don't lag a full day).
  cron.schedule("15 * * * *", async () => {
    try {
      await cleanupExpiredStories();
    } catch (error: any) {
      console.error("[CRON] Error expiring stories:", error.message);
    }
  });

  // Daily at 3:30 AM ET: sweep orphaned upload files.
  cron.schedule(
    "30 3 * * *",
    async () => {
      try {
        await sweepOrphanedMedia();
      } catch (error: any) {
        console.error("[CRON] Error sweeping orphaned media:", error.message);
      }
    },
    { timezone: "America/New_York" },
  );

  console.log(
    "Stories cron scheduled (hourly expiry + 3:30 AM ET orphan sweep).",
  );
}
