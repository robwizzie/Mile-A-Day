import { Response } from "express";
import fs from "fs";
import path from "path";
import sharp from "sharp";
import { AuthenticatedRequest } from "../middleware/auth.js";
import {
  createPost,
  getStoriesRail,
  getUserActiveStories,
  markStoryViewed,
  getFeed,
  getPostAuthor,
  softDeletePost,
  moderatorDeletePost,
  hasAcceptedTerms,
  acceptTerms,
  PostStatsSnapshot,
} from "../services/postService.js";
import {
  reportPost,
  REPORT_REASONS,
  ReportReason,
} from "../services/moderationService.js";
import { getDailyGoalStatus } from "../services/workoutService.js";
import { hasUnlimitedActions } from "../services/privilegedUsers.js";

const POSTS_MEDIA_PREFIX = "/uploads/posts/";
const MAX_CAPTION = 280;
const DEFAULT_FEED_LIMIT = 20;
const MAX_FEED_LIMIT = 50;

/**
 * Upload a post photo. The image arrives already flattened (run-stats overlay
 * baked in by the client). Mirrors uploadProfileImage: Multer memory buffer →
 * Sharp auto-orient + resize + JPEG → /uploads/posts/. Returns the media_url
 * to reference in a subsequent POST /posts.
 */
export async function uploadPostMedia(
  req: AuthenticatedRequest,
  res: Response,
) {
  const userId = req.userId!;
  if (!req.file) {
    return res.status(400).json({ error: "No image file provided" });
  }
  try {
    const filename = `${userId}-${Date.now()}.jpg`;
    const outputPath = path.join(process.cwd(), "uploads", "posts", filename);
    await sharp(req.file.buffer)
      .rotate() // honor EXIF orientation before resizing (portrait photos)
      .resize(1080, 1920, { fit: "inside", withoutEnlargement: true })
      .jpeg({ quality: 82 })
      .toFile(outputPath);

    res.json({ media_url: `${POSTS_MEDIA_PREFIX}${filename}` });
  } catch (error) {
    res.status(500).json({
      error: "Post media upload failed",
      message: error instanceof Error ? error.message : "Unknown error",
    });
  }
}

export async function createPostController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const userId = req.userId!;
  const {
    media_url,
    caption,
    workout_id,
    share_to_feed,
    share_to_story,
    stats_snapshot,
  } = req.body ?? {};

  try {
    // Validate media_url points at our own posts upload dir and exists on disk.
    if (
      typeof media_url !== "string" ||
      !media_url.startsWith(POSTS_MEDIA_PREFIX) ||
      media_url.includes("..")
    ) {
      return res
        .status(400)
        .json({ error: "A valid uploaded media_url is required" });
    }
    const onDisk = path.join(process.cwd(), media_url.replace(/^\//, ""));
    if (!fs.existsSync(onDisk)) {
      return res
        .status(400)
        .json({ error: "media_url does not reference an uploaded file" });
    }

    const shareToFeed = share_to_feed !== false; // default true
    const shareToStory = share_to_story === true; // default false
    if (!shareToFeed && !shareToStory) {
      return res
        .status(400)
        .json({ error: "A post must be shared to the feed, a story, or both" });
    }

    if (
      caption != null &&
      (typeof caption !== "string" || caption.length > MAX_CAPTION)
    ) {
      return res.status(400).json({
        error: `caption must be a string of at most ${MAX_CAPTION} characters`,
      });
    }

    // EULA / UGC terms gate (App Store Guideline 1.2).
    if (!(await hasAcceptedTerms(userId))) {
      return res.status(403).json({ error: "terms_not_accepted" });
    }

    // Authoritative mile-completion gate — recomputed from DB, never trusts client.
    const goal = await getDailyGoalStatus(userId);
    if (!goal.completed) {
      return res.status(403).json({
        error: "mile_not_completed",
        miles: goal.miles,
        goal_miles: goal.goalMiles,
      });
    }

    const post = await createPost({
      userId,
      mediaUrl: media_url,
      caption: typeof caption === "string" ? caption.trim() || null : null,
      workoutId: typeof workout_id === "string" ? workout_id : null,
      localDate: goal.localDate,
      shareToFeed,
      shareToStory,
      statsSnapshot: (stats_snapshot ?? null) as PostStatsSnapshot | null,
    });

    res.status(201).json(post);
  } catch (error: any) {
    console.error("Error creating post:", error.message);
    res.status(500).json({ error: "Error creating post" });
  }
}

export async function getStoriesRailController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    res.status(200).json(await getStoriesRail(req.userId!));
  } catch (error: any) {
    console.error("Error fetching stories rail:", error.message);
    res.status(500).json({ error: "Error fetching stories" });
  }
}

export async function getUserStoriesController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    res
      .status(200)
      .json(await getUserActiveStories(req.userId!, req.params.userId));
  } catch (error: any) {
    console.error("Error fetching user stories:", error.message);
    res.status(500).json({ error: "Error fetching stories" });
  }
}

export async function markStoryViewedController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    await markStoryViewed(req.userId!, req.params.postId);
    res.json({ ok: true });
  } catch (error: any) {
    console.error("Error marking story viewed:", error.message);
    res.status(500).json({ error: "Error marking story viewed" });
  }
}

export async function getFeedController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const rawLimit = parseInt(String(req.query.limit ?? ""), 10);
    const limit = Number.isFinite(rawLimit)
      ? Math.min(Math.max(rawLimit, 1), MAX_FEED_LIMIT)
      : DEFAULT_FEED_LIMIT;
    const before =
      typeof req.query.before === "string" ? req.query.before : null;
    const items = await getFeed(req.userId!, limit, before);
    const nextBefore =
      items.length === limit ? items[items.length - 1].created_at : null;
    res.status(200).json({ items, next_before: nextBefore });
  } catch (error: any) {
    console.error("Error fetching feed:", error.message);
    res.status(500).json({ error: "Error fetching feed" });
  }
}

export async function deletePostController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const userId = req.userId!;
  const postId = req.params.postId;
  try {
    const deleted = await softDeletePost(userId, postId);
    if (deleted) return res.json({ ok: true });

    // Not the author — allow admins to remove objectionable content (1.2).
    if (await hasUnlimitedActions(userId)) {
      const modDeleted = await moderatorDeletePost(postId);
      if (modDeleted) return res.json({ ok: true });
    }
    return res
      .status(403)
      .json({ error: "You can only delete your own posts" });
  } catch (error: any) {
    console.error("Error deleting post:", error.message);
    res.status(500).json({ error: "Error deleting post" });
  }
}

export async function reportPostController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const reporterId = req.userId!;
  const postId = req.params.postId;
  const { reason, details } = req.body ?? {};
  try {
    if (!REPORT_REASONS.includes(reason)) {
      return res
        .status(400)
        .json({ error: `reason must be one of ${REPORT_REASONS.join(", ")}` });
    }
    const author = await getPostAuthor(postId);
    if (!author) return res.status(404).json({ error: "Post not found" });
    if (author === reporterId)
      return res.status(400).json({ error: "You can't report your own post" });

    await reportPost(
      reporterId,
      postId,
      reason as ReportReason,
      typeof details === "string" ? details : undefined,
    );
    res.status(201).json({ message: "Report received" });
  } catch (error: any) {
    console.error("Error reporting post:", error.message);
    res.status(500).json({ error: "Error reporting post" });
  }
}

/** GET /posts/terms — has the user accepted the UGC terms? */
export async function getTermsStatusController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    res.status(200).json({ accepted: await hasAcceptedTerms(req.userId!) });
  } catch (error: any) {
    console.error("Error fetching terms status:", error.message);
    res.status(500).json({ error: "Error fetching terms status" });
  }
}

/** POST /posts/terms/accept — record one-time terms acceptance. */
export async function acceptTermsController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const acceptedAt = await acceptTerms(req.userId!);
    res.status(200).json({ accepted: true, accepted_at: acceptedAt });
  } catch (error: any) {
    console.error("Error accepting terms:", error.message);
    res.status(500).json({ error: "Error accepting terms" });
  }
}
