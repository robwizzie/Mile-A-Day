import { PostgresService } from "./DbService.js";
import { sendPush } from "./pushNotificationService.js";
import { shouldSendNotification } from "./notificationSettingsService.js";
import { visiblePostAuthor, acceptedCoauthor } from "./postService.js";
import {
  resolveMentions,
  notifyMentions,
  MentionedUser,
} from "./mentionService.js";

const db = PostgresService.getInstance();

export interface CommentRow {
  comment_id: string;
  post_id: string;
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  parent_comment_id: string | null;
  content: string;
  created_at: string;
  is_self: boolean;
}

const COMMENT_SELECT = `
	c.comment_id, c.post_id, c.user_id,
	u.username, u.first_name, u.last_name, u.profile_image_url,
	c.parent_comment_id, c.content, c.created_at,
	(c.user_id = $1) AS is_self`;

/**
 * All live comments on a post, oldest first (client groups replies under
 * their parent_comment_id). Comments from users blocked either way vs the
 * viewer are hidden. Returns null when the post isn't visible to the viewer.
 */
export async function listComments(
  viewerId: string,
  postId: string,
): Promise<CommentRow[] | null> {
  const author = await visiblePostAuthor(viewerId, postId);
  if (!author) return null;
  // ponytail: no pagination — friends-only posts see tens of comments, not
  // thousands. Add a `before` cursor when posts approach the cap.
  return db.query<CommentRow>(
    `SELECT ${COMMENT_SELECT}
		 FROM post_comments c
		 JOIN users u ON u.user_id = c.user_id
		 WHERE c.post_id = $2 AND c.deleted_at IS NULL
			 AND NOT EXISTS (
				 SELECT 1 FROM user_blocks b
				 WHERE (b.blocker_id = $1 AND b.blocked_id = c.user_id)
						OR (b.blocker_id = c.user_id AND b.blocked_id = $1)
			 )
		 ORDER BY c.created_at ASC
		 LIMIT 500`,
    [viewerId, postId],
  );
}

/**
 * Add a comment (or a reply when parentCommentId is set). One level of
 * nesting like Instagram: replying to a reply re-roots onto the top-level
 * parent. Notifies the post author (and the parent comment's author on a
 * reply) — fire-and-forget, gated on the shared social-interactions pref
 * ("hype", same bucket story reactions use).
 */
export async function addComment(
  commenterId: string,
  postId: string,
  content: string,
  parentCommentId?: string | null,
): Promise<CommentRow | "not_found" | "parent_not_found"> {
  const postAuthor = await visiblePostAuthor(commenterId, postId);
  if (!postAuthor) return "not_found";

  let parentId: string | null = null;
  let parentAuthor: string | null = null;
  if (parentCommentId) {
    const parents = await db.query<{
      comment_id: string;
      parent_comment_id: string | null;
      user_id: string;
    }>(
      `SELECT comment_id, parent_comment_id, user_id FROM post_comments
			 WHERE comment_id = $1 AND post_id = $2 AND deleted_at IS NULL`,
      [parentCommentId, postId],
    );
    if (parents.length === 0) return "parent_not_found";
    // Re-root replies-to-replies onto the top-level comment (Instagram rule).
    parentId = parents[0].parent_comment_id ?? parents[0].comment_id;
    parentAuthor = parents[0].user_id;
  }

  const rows = await db.query<CommentRow>(
    `WITH inserted AS (
			INSERT INTO post_comments (post_id, user_id, parent_comment_id, content)
			VALUES ($2, $1, $3, $4)
			RETURNING *
		)
		SELECT ${COMMENT_SELECT}
		FROM inserted c
		JOIN users u ON u.user_id = c.user_id`,
    [commenterId, postId, parentId, content],
  );
  const comment = rows[0];

  notifyForComment(comment, commenterId, postAuthor, parentAuthor).catch(
    (e: any) => console.error("[addComment] notify failed:", e?.message ?? e),
  );
  return comment;
}

/**
 * Push "X commented / replied" to the post author + parent-comment author,
 * and "X mentioned you" to @mentioned users. A recipient gets at most ONE
 * push per comment — mention wins over comment/reply.
 */
async function notifyForComment(
  comment: CommentRow,
  commenterId: string,
  postAuthor: string,
  parentAuthor: string | null,
): Promise<void> {
  let mentioned: MentionedUser[] = [];
  try {
    mentioned = await resolveMentions(comment.content, commenterId);
  } catch (e: any) {
    console.error("[notifyForComment] mentions failed:", e?.message ?? e);
  }
  const mentionedIds = new Set(mentioned.map((m) => m.user_id));
  notifyMentions(
    commenterId,
    mentioned,
    comment.post_id,
    comment.content,
    "comment",
  ).catch((e: any) =>
    console.error("[notifyForComment] mention push failed:", e?.message ?? e),
  );

  const recipients = new Set<string>();
  if (postAuthor !== commenterId && !mentionedIds.has(postAuthor))
    recipients.add(postAuthor);
  // Accepted collab posts notify BOTH authors.
  const coauthor = await acceptedCoauthor(comment.post_id);
  if (coauthor && coauthor !== commenterId && !mentionedIds.has(coauthor))
    recipients.add(coauthor);
  if (
    parentAuthor &&
    parentAuthor !== commenterId &&
    !mentionedIds.has(parentAuthor)
  )
    recipients.add(parentAuthor);
  if (recipients.size === 0) return;

  const sender = await db.query<{ username: string | null }>(
    `SELECT username FROM users WHERE user_id = $1`,
    [commenterId],
  );
  const name = sender[0]?.username ?? "A friend";
  const body = comment.content.slice(0, 120);

  for (const recipient of recipients) {
    const shouldSend = await shouldSendNotification(
      recipient,
      commenterId,
      "hype",
    );
    if (!shouldSend) continue;
    const replied =
      recipient === parentAuthor && recipient !== postAuthor &&
      recipient !== coauthor;
    sendPush(recipient, {
      title: replied
        ? `${name} replied to your comment 💬`
        : `${name} commented on your post 💬`,
      body,
      type: "post_comment",
      data: {
        user_id: commenterId,
        post_id: comment.post_id,
        comment_id: comment.comment_id,
      },
    }).catch((e: any) =>
      console.error("[notifyForComment] push failed:", e?.message ?? e),
    );
  }
}

/**
 * Soft-delete a comment. Allowed for the comment's author and the post's
 * author(s) — including an accepted collab coauthor (owners moderate their
 * own post, Instagram-style). Deleting a top-level comment also soft-deletes
 * its replies.
 */
export async function deleteComment(
  callerId: string,
  commentId: string,
): Promise<"ok" | "not_found" | "forbidden"> {
  const rows = await db.query<{ comment_id: string }>(
    `UPDATE post_comments c SET deleted_at = NOW()
		 FROM posts p
		 WHERE c.comment_id = $1 AND c.deleted_at IS NULL
			 AND p.post_id = c.post_id
			 AND (c.user_id = $2 OR p.user_id = $2
				 OR (p.coauthor_user_id = $2 AND p.coauthor_status = 'accepted'))
		 RETURNING c.comment_id`,
    [commentId, callerId],
  );
  if (rows.length === 0) {
    const exists = await db.query(
      `SELECT 1 FROM post_comments WHERE comment_id = $1 AND deleted_at IS NULL`,
      [commentId],
    );
    return exists.length > 0 ? "forbidden" : "not_found";
  }
  await db.query(
    `UPDATE post_comments SET deleted_at = NOW()
		 WHERE parent_comment_id = $1 AND deleted_at IS NULL`,
    [commentId],
  );
  return "ok";
}
