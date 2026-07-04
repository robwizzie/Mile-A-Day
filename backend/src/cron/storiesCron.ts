import cron from "node-cron";
import fs from "fs";
import path from "path";
import { PostgresService } from "../services/DbService.js";

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

  console.log("Stories cron scheduled (3:30 AM ET orphan sweep).");
}
