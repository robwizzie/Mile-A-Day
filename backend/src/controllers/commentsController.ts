import { Response } from "express";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  listComments,
  listWorkoutComments,
  addComment,
  addWorkoutComment,
  deleteComment,
} from "../services/commentService.js";
import { hasAcceptedTerms } from "../services/postService.js";
import {
  reportComment,
  REPORT_REASONS,
  ReportReason,
} from "../services/moderationService.js";
import { isUuid } from "./postsController.js";
import {
  isCommentSticker,
  stickerFallbackText,
} from "../services/commentStickers.js";

const MAX_COMMENT = 1000;

/**
 * The comment body: a sticker (`sticker_id`, its stand-in text stored as
 * content, any typed text ignored) or text (`content`, 1-MAX_COMMENT chars).
 */
function parseCommentBody(
  body: any,
):
  | { content: string; stickerId: string | null }
  | { error: string } {
  if (body?.sticker_id != null) {
    if (!isCommentSticker(body.sticker_id)) return { error: "invalid_sticker" };
    return {
      content: stickerFallbackText(body.sticker_id),
      stickerId: body.sticker_id,
    };
  }
  const content = typeof body?.content === "string" ? body.content.trim() : "";
  if (content.length === 0 || content.length > MAX_COMMENT) {
    return { error: `content must be 1-${MAX_COMMENT} characters` };
  }
  return { content, stickerId: null };
}

/** GET /posts/:postId/comments — all live comments, oldest first. */
export async function listCommentsController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!isUuid(req.params.postId)) {
      return res.status(404).json({ error: "post_not_found" });
    }
    const comments = await listComments(req.userId!, req.params.postId);
    if (comments === null) {
      return res.status(404).json({ error: "post_not_found" });
    }
    res.json({ comments });
  } catch (error: any) {
    console.error("Error listing comments:", error.message);
    res.status(500).json({ error: "Error listing comments" });
  }
}

/** GET /posts/workouts/:workoutId/comments — comments on a raw feed workout. */
export async function listWorkoutCommentsController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const workoutId =
      typeof req.params.workoutId === "string" ? req.params.workoutId : "";
    if (!workoutId) {
      return res.status(404).json({ error: "workout_not_found" });
    }
    const comments = await listWorkoutComments(req.userId!, workoutId);
    if (comments === null) {
      return res.status(404).json({ error: "workout_not_found" });
    }
    res.json({ comments });
  } catch (error: any) {
    console.error("Error listing workout comments:", error.message);
    res.status(500).json({ error: "Error listing comments" });
  }
}

/** POST /posts/:postId/comments — { content | sticker_id, parent_comment_id? } */
export async function addCommentController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!isUuid(req.params.postId)) {
      return res.status(404).json({ error: "post_not_found" });
    }
    const parsed = parseCommentBody(req.body);
    if ("error" in parsed) {
      return res.status(400).json({ error: parsed.error });
    }
    const parentCommentId = req.body?.parent_comment_id;
    if (parentCommentId != null && !isUuid(parentCommentId)) {
      return res.status(400).json({ error: "invalid_parent_comment_id" });
    }
    // EULA / UGC terms gate (App Store Guideline 1.2), same as posting.
    if (!(await hasAcceptedTerms(req.userId!))) {
      return res.status(403).json({ error: "terms_not_accepted" });
    }
    const result = await addComment(
      req.userId!,
      req.params.postId,
      parsed.content,
      parentCommentId ?? null,
      parsed.stickerId,
    );
    if (result === "not_found") {
      return res.status(404).json({ error: "post_not_found" });
    }
    if (result === "parent_not_found") {
      return res.status(404).json({ error: "comment_not_found" });
    }
    res.status(201).json({ comment: result });
  } catch (error: any) {
    console.error("Error adding comment:", error.message);
    res.status(500).json({ error: "Error adding comment" });
  }
}

/** POST /posts/workouts/:workoutId/comments — { content | sticker_id, parent_comment_id? } */
export async function addWorkoutCommentController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const workoutId =
      typeof req.params.workoutId === "string" ? req.params.workoutId : "";
    if (!workoutId) {
      return res.status(404).json({ error: "workout_not_found" });
    }
    const parsed = parseCommentBody(req.body);
    if ("error" in parsed) {
      return res.status(400).json({ error: parsed.error });
    }
    const parentCommentId = req.body?.parent_comment_id;
    if (parentCommentId != null && !isUuid(parentCommentId)) {
      return res.status(400).json({ error: "invalid_parent_comment_id" });
    }
    if (!(await hasAcceptedTerms(req.userId!))) {
      return res.status(403).json({ error: "terms_not_accepted" });
    }
    const result = await addWorkoutComment(
      req.userId!,
      workoutId,
      parsed.content,
      parentCommentId ?? null,
      parsed.stickerId,
    );
    if (result === "not_found") {
      return res.status(404).json({ error: "workout_not_found" });
    }
    if (result === "parent_not_found") {
      return res.status(404).json({ error: "comment_not_found" });
    }
    res.status(201).json({ comment: result });
  } catch (error: any) {
    console.error("Error adding workout comment:", error.message);
    res.status(500).json({ error: "Error adding comment" });
  }
}

/** DELETE /posts/comments/:commentId — comment author or post author. */
export async function deleteCommentController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!isUuid(req.params.commentId)) {
      return res.status(404).json({ error: "comment_not_found" });
    }
    const result = await deleteComment(req.userId!, req.params.commentId);
    if (result === "not_found") {
      return res.status(404).json({ error: "comment_not_found" });
    }
    if (result === "forbidden") {
      return res.status(403).json({ error: "not_allowed" });
    }
    res.json({ message: "Comment deleted" });
  } catch (error: any) {
    console.error("Error deleting comment:", error.message);
    res.status(500).json({ error: "Error deleting comment" });
  }
}

/** POST /posts/comments/:commentId/report — { reason, details? } */
export async function reportCommentController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!isUuid(req.params.commentId)) {
      return res.status(404).json({ error: "comment_not_found" });
    }
    const { reason, details } = req.body ?? {};
    if (!REPORT_REASONS.includes(reason)) {
      return res
        .status(400)
        .json({ error: `reason must be one of ${REPORT_REASONS.join(", ")}` });
    }
    const result = await reportComment(
      req.userId!,
      req.params.commentId,
      reason as ReportReason,
      typeof details === "string" ? details : undefined,
    );
    if (result === "not_found") {
      return res.status(404).json({ error: "comment_not_found" });
    }
    if (result === "own_comment") {
      return res
        .status(400)
        .json({ error: "You can't report your own comment" });
    }
    res.status(201).json({ message: "Report received" });
  } catch (error: any) {
    console.error("Error reporting comment:", error.message);
    res.status(500).json({ error: "Error reporting comment" });
  }
}
