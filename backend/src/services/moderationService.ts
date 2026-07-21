import { PostgresService } from "./DbService.js";
import { updateFriendship } from "./friendshipService.js";

const db = PostgresService.getInstance();

export const REPORT_REASONS = [
  "spam",
  "nudity",
  "harassment",
  "violence",
  "other",
] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

/**
 * All user ids the viewer should not see content from, in EITHER direction:
 * people the viewer blocked, plus people who blocked the viewer. Used as a
 * NOT-IN subquery across every post/story read so blocks are symmetric.
 */
export async function getBlockedIds(userId: string): Promise<string[]> {
  const rows = await db.query<{ uid: string }>(
    `SELECT blocked_id AS uid FROM user_blocks WHERE blocker_id = $1
		 UNION
		 SELECT blocker_id AS uid FROM user_blocks WHERE blocked_id = $1`,
    [userId],
  );
  return rows.map((r) => r.uid);
}

/**
 * Record an abuse report on a post. Idempotent per (post, reporter) via the
 * partial unique index — repeat reports are silently ignored.
 */
export async function reportPost(
  reporterId: string,
  postId: string,
  reason: ReportReason,
  details?: string,
): Promise<void> {
  await db.query(
    `INSERT INTO post_reports (post_id, reporter_id, reason, details)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (post_id, reporter_id) DO NOTHING`,
    [postId, reporterId, reason, details ?? null],
  );
}

/**
 * Record an abuse report on a comment (App Store Guideline 1.2). Idempotent
 * per (comment, reporter) — repeat reports are silently ignored.
 */
export async function reportComment(
  reporterId: string,
  commentId: string,
  reason: ReportReason,
  details?: string,
): Promise<"ok" | "not_found" | "own_comment"> {
  const rows = await db.query<{ user_id: string }>(
    `SELECT user_id FROM post_comments WHERE comment_id = $1 AND deleted_at IS NULL`,
    [commentId],
  );
  if (rows.length === 0) return "not_found";
  if (rows[0].user_id === reporterId) return "own_comment";
  await db.query(
    `INSERT INTO comment_reports (comment_id, reporter_id, reason, details)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (comment_id, reporter_id) DO NOTHING`,
    [commentId, reporterId, reason, details ?? null],
  );
  return "ok";
}

/**
 * Block another user. Also tears down any friendship in both directions so the
 * relationship-gated surfaces (hype, feed circle) drop immediately.
 */
export async function blockUser(
  blockerId: string,
  blockedId: string,
): Promise<void> {
  await db.query(
    `INSERT INTO user_blocks (blocker_id, blocked_id)
		 VALUES ($1, $2)
		 ON CONFLICT (blocker_id, blocked_id) DO NOTHING`,
    [blockerId, blockedId],
  );
  // Best-effort friendship teardown; a missing friendship is not an error.
  try {
    await updateFriendship(blockerId, blockedId, "removed");
  } catch {
    /* no friendship to remove */
  }
}

export async function unblockUser(
  blockerId: string,
  blockedId: string,
): Promise<void> {
  await db.query(
    `DELETE FROM user_blocks WHERE blocker_id = $1 AND blocked_id = $2`,
    [blockerId, blockedId],
  );
}
