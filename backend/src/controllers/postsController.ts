import { Response } from "express";
import crypto from "crypto";
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
  getUnifiedFeed,
  getUserPosts,
  getFeedEntryForPost,
  getUserTaggedPosts,
  notifyFriendsOfPost,
  getPostAuthor,
  softDeletePost,
  moderatorDeletePost,
  updateOwnPost,
  hasAcceptedTerms,
  acceptTerms,
  getStoryViewers,
  getStoryReactors,
  reactToStory,
  getOwnPostMemories,
  getOwnedWorkoutDistance,
  getOwnedWorkoutRollupDistance,
  getPostWindowStatus,
  photoSourceRequiresCameraWindow,
  addCrewPhoto,
  notifyCrewPhoto,
  POST_WINDOW_MS,
  lockUnearnedPhotos,
  ALLOWED_STORY_REACTIONS,
  PostStatsSnapshot,
  sanitizeGhostStats,
  type ViewerGoalGate,
} from "../services/postService.js";
import {
  reportPost,
  REPORT_REASONS,
  ReportReason,
} from "../services/moderationService.js";
import { notifyCaptionMentions } from "../services/mentionService.js";
import {
  notifyCoauthorInvite,
  notifyCoauthorAccepted,
  respondToCoauthorInvite,
  respondToMultiCoauthorInvite,
  postAuthorId,
  setCoauthorProfileVisibility,
} from "../services/postService.js";
import {
  getActiveStreak,
  getDailyGoalStatus,
} from "../services/workoutService.js";
import { CLIENT_FEATURES, userSupports } from "../services/clientFeatures.js";
import { hasUnlimitedActions } from "../services/privilegedUsers.js";
import { evaluateSocialBadgesForUser } from "../services/badgeService.js";
import { logError } from "../services/errorLogService.js";
import {
  signMediaUrl,
  signMediaUrlsDeep,
  stripMediaQuery,
} from "../services/mediaSigningService.js";

// Friend "new post" push notifications: LIVE as of the App Store build that
// ships the Feed/Stories UI (July 2026 update). Recipients are additionally
// filtered to builds that can actually open the feed (see notifyFriendsOfPost).
const FRIEND_POST_NOTIFICATIONS_ENABLED = true;

const POSTS_MEDIA_PREFIX = "/uploads/posts/";
const MAX_CAPTION = 280;
const DEFAULT_FEED_LIMIT = 20;
const MAX_FEED_LIMIT = 50;

// posts.post_id is a uuid — validate route params before they hit a ::uuid
// cast, so garbage ids 404 instead of bubbling a cast error into a 500.
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: string | undefined): value is string {
  return typeof value === "string" && UUID_RE.test(value);
}

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
    // Random suffix: two uploads in the same millisecond (double-tap retry)
    // must not overwrite each other. The `<userId>-` prefix doubles as the
    // ownership check when the media_url is referenced in POST /posts.
    const filename = `${userId}-${Date.now()}-${crypto.randomBytes(4).toString("hex")}.jpg`;
    const outputPath = path.join(process.cwd(), "uploads", "posts", filename);
    await sharp(req.file.buffer)
      .rotate() // honor EXIF orientation before resizing (portrait photos)
      .resize(1080, 1920, { fit: "inside", withoutEnlargement: true })
      .jpeg({ quality: 82 })
      .toFile(outputPath);

    res.json({ media_url: signMediaUrl(`${POSTS_MEDIA_PREFIX}${filename}`) });
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
    is_auto,
    include_route,
    coauthor_user_id,
    coauthor_user_ids,
    buddy_session_id,
    posted_live,
    photo_source,
  } = req.body ?? {};

  try {
    // Clients echo the signed url from the upload/feed response (promote
    // flow) — store the bare path, signatures are minted per-response.
    const mediaUrl =
      typeof media_url === "string" ? stripMediaQuery(media_url) : media_url;
    // Validate media_url points at our own posts upload dir and exists on disk.
    if (
      typeof mediaUrl !== "string" ||
      !mediaUrl.startsWith(POSTS_MEDIA_PREFIX) ||
      mediaUrl.includes("..")
    ) {
      return res
        .status(400)
        .json({ error: "A valid uploaded media_url is required" });
    }
    const onDisk = path.join(process.cwd(), mediaUrl.replace(/^\//, ""));
    if (!fs.existsSync(onDisk)) {
      return res
        .status(400)
        .json({ error: "media_url does not reference an uploaded file" });
    }
    // Ownership: upload filenames are `<userId>-<ts>-<rand>.jpg`, and media
    // urls are visible to the whole circle — without this check anyone could
    // republish a friend's photo (including story-only photos) as their own.
    if (!path.basename(mediaUrl).startsWith(`${userId}-`)) {
      return res
        .status(403)
        .json({ error: "media_url must reference your own upload" });
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

    // A photo belongs to the walk or run that earned it. Which clock that
    // requires depends on where the photo came from (see PostPhotoSource):
    // a live capture is held to the ten minutes after a qualifying workout
    // lands, while a photo picked out of the camera roll — already proven by
    // its capture time to be FROM the walk — is good for the rest of the day.
    // Both still require a qualifying workout today, so neither is a route to
    // posting without moving.
    //
    // Two deliberate exemptions:
    //  - Auto posts. They're the generated route/stats card the app writes when
    //    the user SKIPS the photo prompt — already bound to their workout by
    //    construction, and blocking them would leave the run with no card.
    //  - Devices that predate the rule. Those builds open the composer whenever
    //    the mile is done, so enforcing here would let someone shoot and edit a
    //    photo and fail only at publish, with no UI that can explain why. They
    //    keep the old behavior until they update (see CLIENT_FEATURES).
    if (
      is_auto !== true &&
      (await userSupports(userId, CLIENT_FEATURES.postWindowV1))
    ) {
      const postWindow = await getPostWindowStatus(userId, goal.localDate);
      const needsCamera = photoSourceRequiresCameraWindow(photo_source);
      const allowed = needsCamera
        ? postWindow.cameraOpen
        : postWindow.photoOpen;
      if (!allowed) {
        // The error STRING is load-bearing: shipped builds match on
        // `post_window_closed` and have copy for it. `reason` is the additive
        // half — it tells a build that knows about the split which of the two
        // gates closed, so it can offer the camera roll instead of a dead end.
        return res.status(403).json({
          error: "post_window_closed",
          reason: needsCamera ? "camera_window_closed" : "no_workout_today",
          photo_open: postWindow.photoOpen,
          window_seconds: Math.round(POST_WINDOW_MS / 1000),
        });
      }
    }

    // Only link the post to a workout the caller actually owns. Workout ids are
    // visible to the whole circle in feed payloads, so an unchecked id would let
    // a user occupy a friend's one-post-per-workout slot (blocking their posts
    // and hiding their workout card). Unknown/foreign ids also FK-fail, so an
    // unlinked post beats a 500 either way.
    let workoutId = typeof workout_id === "string" ? workout_id : null;
    let linkedWorkoutDistance: number | null = null;
    if (workoutId) {
      linkedWorkoutDistance = await getOwnedWorkoutDistance(userId, workoutId);
    }
    if (workoutId && linkedWorkoutDistance == null) {
      if (is_auto === true) {
        return res.status(400).json({ error: "auto_post_workout_unavailable" });
      }
      console.warn(
        `[createPost] Ignoring workout_id not owned by poster ${userId}`,
      );
      workoutId = null;
    }

    const hasStats =
      stats_snapshot != null &&
      typeof stats_snapshot === "object" &&
      !Array.isArray(stats_snapshot);

    // Defensive guard for already-shipped clients: older auto-card builders
    // baked the author's whole-day distance into a card linked to one workout.
    // Rejecting the bad auto post leaves the raw workout feed card visible
    // instead of hiding it behind a misleading generated image.
    //
    // The DAY'S ROLLUP is legitimate on the anchor of a multi-segment mile,
    // though — that is exactly the number the feed restates the card with, so a
    // card baked with the single leg reads 0.33 next to a 1.06 headline. Accept
    // either the leg or the rollup and let the read path do the rest.
    if (
      workoutId &&
      is_auto === true &&
      linkedWorkoutDistance != null &&
      hasStats
    ) {
      const claimedDistance = Number(
        (stats_snapshot as PostStatsSnapshot).distance,
      );
      if (Number.isFinite(claimedDistance)) {
        const rollupDistance = await getOwnedWorkoutRollupDistance(
          userId,
          workoutId,
        );
        const matches = [linkedWorkoutDistance, rollupDistance].some(
          (candidate) =>
            candidate != null && Math.abs(claimedDistance - candidate) <= 0.05,
        );
        if (!matches) {
          return res.status(400).json({ error: "auto_post_stats_mismatch" });
        }
      }
    }

    // The streak baked into a post is the one number a client can get wrong and
    // then keep wrong forever: it's a snapshot, never restated on read, and the
    // app's local streak is quarantine-gated (it refuses to believe a big drop
    // until the server confirms it). So a post made right after a missed day
    // could sit in the feed claiming a streak the author no longer has. Stamp
    // the server's value over it — only when the client sent one, so a post
    // that deliberately carries no streak chip stays that way.
    let statsSnapshot = sanitizeGhostStats(
      (stats_snapshot ?? null) as PostStatsSnapshot | null,
    );
    if (hasStats && statsSnapshot?.streak != null) {
      try {
        const { streak } = await getActiveStreak(userId);
        statsSnapshot = { ...statsSnapshot, streak };
      } catch (err) {
        // Never fail a post over a cosmetic chip — keep the client's number.
        console.warn("[createPost] streak restatement failed:", err);
      }
    }

    const post = await createPost({
      userId,
      mediaUrl,
      caption: typeof caption === "string" ? caption.trim() || null : null,
      workoutId,
      localDate: goal.localDate,
      shareToFeed,
      shareToStory,
      statsSnapshot,
      // Absent on legacy clients — createPost keeps the old upsert behavior
      // and owns the include_route default.
      isAuto: typeof is_auto === "boolean" ? is_auto : undefined,
      includeRoute:
        typeof include_route === "boolean" ? include_route : undefined,
      coauthorUserId:
        typeof coauthor_user_id === "string" ? coauthor_user_id : null,
      // Multi-person collab (Buddy Walks). Absent on every shipped client, so
      // the single-coauthor path above is untouched for them.
      coauthorUserIds: Array.isArray(coauthor_user_ids)
        ? coauthor_user_ids.filter((id: unknown) => typeof id === "string")
        : null,
      buddySessionId:
        typeof buddy_session_id === "string" ? buddy_session_id : null,
      // Client-owned FRESH claim (its 10-min window anchors to when the app
      // saw the run). Cosmetic; legacy clients omit it and get the feed
      // query's server-side derivation instead.
      postedLive: posted_live === true,
    });

    // Collab tag — fire-and-forget push to the person just added. Gated on
    // 'accepted', which is now what createPost writes: tagging is immediate,
    // so there is no pending state left to wait for. (Checking for 'pending'
    // here would silence the notification completely.)
    if (post.coauthor_user_id && post.coauthor_status === "accepted") {
      notifyCoauthorInvite(userId, post.coauthor_user_id, post.post_id).catch(
        () => {},
      );
    }

    // Fire-and-forget: tell friends about a new DELIBERATE post — the photo
    // (or story) the user chose to share. Auto route/stats cards stay silent,
    // and one createPost call produces exactly ONE notification even when it
    // goes to both the story and the feed. Never blocks the response.
    if (FRIEND_POST_NOTIFICATIONS_ENABLED && post.is_auto !== true) {
      notifyFriendsOfPost({
        authorId: userId,
        postId: post.post_id,
        caption: post.caption,
        toFeed: shareToFeed,
        toStory: shareToStory,
        localDate: goal.localDate,
      }).catch(() => {});
    }
    // Caption @mentions ("ran with @rob") — personal, so not behind the
    // friend-post flag. ponytail: a legacy-client caption re-upsert can
    // re-notify; rare enough to accept over tracking notified state.
    if (shareToFeed && !post.is_auto && post.caption) {
      notifyCaptionMentions(userId, post.post_id, post.caption).catch(() => {});
    }
    // Re-evaluate story badges (first story, X stories) in the background.
    if (shareToStory) {
      evaluateSocialBadgesForUser(userId).catch(() => {});
    }

    res.status(201).json(signMediaUrlsDeep(post));
  } catch (error: any) {
    // One deliberate post per workout — the slot is taken until that post is
    // deleted. Surface as a conflict the client can message, not a 500.
    if (error?.message === "workout_already_posted") {
      return res.status(409).json({ error: "workout_already_posted" });
    }
    // Coauthor must be an accepted friend with no blocks either way.
    if (error?.message === "invalid_coauthor") {
      return res.status(400).json({ error: "invalid_coauthor" });
    }
    console.error("Error creating post:", error.message);
    res.status(500).json({ error: "Error creating post" });
  }
}

export async function getStoriesRailController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    res.status(200).json(signMediaUrlsDeep(await getStoriesRail(req.userId!)));
  } catch (error: any) {
    console.error("Error fetching stories rail:", error.message);
    logError("api", `stories rail failed: ${error.message}`, {
      userId: req.userId ?? null,
      context: { path: "/posts/stories" },
    });
    res.status(500).json({ error: "Error fetching stories" });
  }
}

export async function getUserStoriesController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const stories = await getUserActiveStories(req.userId!, req.params.userId);
    // Gate today's story photos the same way the feed/profile do — a viewer who
    // hasn't finished their own mile can't pull a friend's today photo. (The
    // client already hides today's stories pre-completion; this closes the
    // server-side bypass so the photo bytes are never handed over.)
    lockUnearnedPhotos(
      stories,
      req.userId!,
      await viewerPhotoGate(req.userId!),
    );
    res.status(200).json(signMediaUrlsDeep(stories));
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
    if (!isUuid(req.params.postId)) {
      return res.status(404).json({ error: "story_not_found" });
    }
    await markStoryViewed(req.userId!, req.params.postId);
    res.json({ ok: true });
  } catch (error: any) {
    console.error("Error marking story viewed:", error.message);
    res.status(500).json({ error: "Error marking story viewed" });
  }
}

/** Who saw the caller's own story (with reactions). 404 unless it's theirs. */
export async function getStoryViewersController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!isUuid(req.params.postId)) {
      return res.status(404).json({ error: "story_not_found" });
    }
    const viewers = await getStoryViewers(req.userId!, req.params.postId);
    if (viewers === null) {
      return res.status(404).json({ error: "story_not_found" });
    }
    res.json({ viewers, count: viewers.length });
  } catch (error: any) {
    console.error("Error getting story viewers:", error.message);
    res.status(500).json({ error: "Error getting story viewers" });
  }
}

/**
 * Who reacted to a story, for the reaction-bubble row shown to ALL circle
 * viewers (not just the author). 404 when the caller can't see the story.
 */
export async function getStoryReactorsController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!isUuid(req.params.postId)) {
      return res.status(404).json({ error: "story_not_found" });
    }
    const reactors = await getStoryReactors(req.userId!, req.params.postId);
    if (reactors === null) {
      return res.status(404).json({ error: "story_not_found" });
    }
    res.json({ reactors, count: reactors.length });
  } catch (error: any) {
    console.error("Error getting story reactors:", error.message);
    res.status(500).json({ error: "Error getting story reactors" });
  }
}

/** Emoji-react to a friend's active story. Re-reacting swaps the emoji. */
export async function reactToStoryController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!isUuid(req.params.postId)) {
      return res.status(404).json({ error: "story_not_found" });
    }
    const emoji = typeof req.body?.emoji === "string" ? req.body.emoji : "";
    if (!ALLOWED_STORY_REACTIONS.has(emoji)) {
      return res.status(400).json({ error: "invalid_reaction" });
    }
    const result = await reactToStory(req.userId!, req.params.postId, emoji);
    if (result === "not_found") {
      return res.status(404).json({ error: "story_not_found" });
    }
    if (result === "forbidden") {
      return res.status(403).json({ error: "not_allowed" });
    }
    res.json({ ok: true });
  } catch (error: any) {
    console.error("Error reacting to story:", error.message);
    res.status(500).json({ error: "Error reacting to story" });
  }
}

/**
 * The caller's own post photos from this day in past years / a week ago / a
 * month ago, for the "On this day" memories surface. Uses the same
 * timezone-aware local date as posting.
 */
export async function getPostMemoriesController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const goal = await getDailyGoalStatus(req.userId!);
    const items = await getOwnPostMemories(req.userId!, goal.localDate);
    res.json({ items: signMediaUrlsDeep(items) });
  } catch (error: any) {
    console.error("Error getting post memories:", error.message);
    res.status(500).json({ error: "Error getting post memories" });
  }
}

/**
 * Repair a keyset cursor whose timezone '+' was decoded as a space. Shipped
 * clients percent-encode cursors with a set that leaves '+' literal, and
 * Express's query parser turns a literal '+' into ' ' — so the old
 * "2026-07-04 12:34:56.123456+00" cursor arrived as "…123456 00" and its
 * `::timestamptz` cast threw, silently killing pagination after page one.
 * New cursors are emitted URL-safe (ISO-8601 "…Z"), but cursors already in
 * the field (and older app builds) still need this rewrite. A valid cursor
 * never legitimately ends in <space><offset-digits>, so the rewrite is safe.
 */
function repairBeforeCursor(req: AuthenticatedRequest): string | null {
  const raw = typeof req.query.before === "string" ? req.query.before : null;
  if (!raw) return null;
  return raw.replace(/ (\d{2}(:?\d{2})?)$/, "+$1");
}

/**
 * The viewer's mile status, used to gate today's photos. Fail-OPEN: a stats
 * hiccup returns `completed:true` so a glitch never blanks the whole feed
 * (better to briefly over-show than to break the surface).
 */
async function viewerPhotoGate(userId: string): Promise<ViewerGoalGate> {
  try {
    const goal = await getDailyGoalStatus(userId);
    return { completed: goal.completed, localDate: goal.localDate };
  } catch (e: any) {
    console.error("[viewerPhotoGate] goal status failed:", e?.message ?? e);
    return { completed: true, localDate: "" };
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
    const before = repairBeforeCursor(req);
    const items = await getFeed(req.userId!, limit, before);
    lockUnearnedPhotos(items, req.userId!, await viewerPhotoGate(req.userId!));
    // `cursor` is the microsecond-precise URL-safe timestamp; created_at
    // (a ms-truncated JS Date) would skip same-millisecond rows at boundaries.
    const last = items[items.length - 1];
    const nextBefore =
      items.length === limit ? (last.cursor ?? last.created_at) : null;
    res
      .status(200)
      .json({ items: signMediaUrlsDeep(items), next_before: nextBefore });
  } catch (error: any) {
    console.error("Error fetching feed:", error.message);
    res.status(500).json({ error: "Error fetching feed" });
  }
}

/** GET /posts/feed/unified — interleaved posts + workout activity, paginated. */
export async function getUnifiedFeedController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const rawLimit = parseInt(String(req.query.limit ?? ""), 10);
    const limit = Number.isFinite(rawLimit)
      ? Math.min(Math.max(rawLimit, 1), MAX_FEED_LIMIT)
      : DEFAULT_FEED_LIMIT;
    const before = repairBeforeCursor(req);
    const items = await getUnifiedFeed(req.userId!, limit, before);
    lockUnearnedPhotos(items, req.userId!, await viewerPhotoGate(req.userId!));
    const last = items[items.length - 1];
    const nextBefore =
      items.length === limit ? (last.cursor ?? last.sort_ts) : null;
    res
      .status(200)
      .json({ items: signMediaUrlsDeep(items), next_before: nextBefore });
  } catch (error: any) {
    console.error("Error fetching unified feed:", error.message);
    // Surface in the error dashboard — the app swallows feed failures
    // silently ("No activity yet"), so this must never be invisible.
    logError("api", `unified feed failed: ${error.message}`, {
      userId: req.userId ?? null,
      context: { path: "/posts/feed/unified" },
    });
    res.status(500).json({ error: "Error fetching feed" });
  }
}

/**
 * GET /posts/:postId — ONE post, shaped exactly like its feed entry.
 *
 * What makes opening a post directly possible: a tap on the profile grid, a
 * mention push, a shared link. Scrolling a paginated feed to find it could
 * never work for a post that's weeks old. 404 covers both "gone" and "not
 * yours to see" so the two are indistinguishable.
 */
export async function getPostController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const postId = req.params.postId;
    if (!isUuid(postId)) {
      return res.status(404).json({ error: "Post not found" });
    }
    const item = await getFeedEntryForPost(req.userId!, postId);
    if (!item) return res.status(404).json({ error: "Post not found" });
    lockUnearnedPhotos([item], req.userId!, await viewerPhotoGate(req.userId!));
    res.status(200).json(signMediaUrlsDeep(item));
  } catch (error: any) {
    console.error("Error fetching post:", error.message);
    res.status(500).json({ error: "Error fetching post" });
  }
}

/** GET /posts/user/:userId — a user's permanent posts for the profile grid. */
export async function getUserPostsController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const rawLimit = parseInt(String(req.query.limit ?? ""), 10);
    const limit = Number.isFinite(rawLimit)
      ? Math.min(Math.max(rawLimit, 1), MAX_FEED_LIMIT)
      : DEFAULT_FEED_LIMIT;
    const before = repairBeforeCursor(req);
    // Story-only posts are private drafts of a sort — only the author may
    // see them, no matter what the query string claims.
    const includeStoryOnly =
      req.query.include_stories === "true" && req.params.userId === req.userId;
    const items = await getUserPosts(
      req.userId!,
      req.params.userId,
      limit,
      before,
      includeStoryOnly,
    );
    lockUnearnedPhotos(items, req.userId!, await viewerPhotoGate(req.userId!));
    const last = items[items.length - 1];
    const nextBefore =
      items.length === limit ? (last.cursor ?? last.created_at) : null;
    res
      .status(200)
      .json({ items: signMediaUrlsDeep(items), next_before: nextBefore });
  } catch (error: any) {
    console.error("Error fetching user posts:", error.message);
    res.status(500).json({ error: "Error fetching posts" });
  }
}

/**
 * GET /posts/user/:userId/tagged — posts the user is tagged in (visible
 * collabs + caption @mentions), the Instagram-style profile "Tagged" tab.
 */
export async function getUserTaggedPostsController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    const rawLimit = parseInt(String(req.query.limit ?? ""), 10);
    const limit = Number.isFinite(rawLimit)
      ? Math.min(Math.max(rawLimit, 1), MAX_FEED_LIMIT)
      : DEFAULT_FEED_LIMIT;
    const before = repairBeforeCursor(req);
    const items = await getUserTaggedPosts(
      req.userId!,
      req.params.userId,
      limit,
      before,
    );
    lockUnearnedPhotos(items, req.userId!, await viewerPhotoGate(req.userId!));
    const last = items[items.length - 1];
    const nextBefore =
      items.length === limit ? (last.cursor ?? last.created_at) : null;
    res
      .status(200)
      .json({ items: signMediaUrlsDeep(items), next_before: nextBefore });
  } catch (error: any) {
    console.error("Error fetching tagged posts:", error.message);
    res.status(500).json({ error: "Error fetching posts" });
  }
}

export async function deletePostController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const userId = req.userId!;
  const postId = req.params.postId;
  try {
    if (!isUuid(postId)) {
      return res.status(404).json({ error: "Post not found" });
    }
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

/**
 * PATCH /posts/:postId — edit a post the caller authored.
 * Body: { caption?: string|null, add_to_feed?: true }.
 * add_to_feed promotes a story-only post onto the feed in place (keeping its
 * original date/media/stats); 409 workout_already_posted when the run already
 * has a deliberate feed post.
 */
export async function updatePostController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const userId = req.userId!;
  const postId = req.params.postId;
  const { caption, add_to_feed } = req.body ?? {};
  try {
    if (!isUuid(postId)) {
      return res.status(404).json({ error: "Post not found" });
    }

    const hasCaption = caption !== undefined;
    if (
      hasCaption &&
      caption !== null &&
      (typeof caption !== "string" || caption.length > MAX_CAPTION)
    ) {
      return res.status(400).json({
        error: `caption must be a string of at most ${MAX_CAPTION} characters`,
      });
    }
    const addToFeed = add_to_feed === true;
    if (!hasCaption && !addToFeed) {
      return res.status(400).json({ error: "Nothing to update" });
    }

    // Promoting a story onto the feed puts a photo on the feed, so it answers
    // to the same rule as creating one — the story viewer's own "Add to feed"
    // routes through createPost, and the two are the same user action on two
    // screens and can't disagree.
    //
    // That rule is the DAY tier, not the camera countdown. The photo was
    // already captured under whichever gate applied when it was taken, so
    // re-charging it the ten minutes would only mean that sharing to your
    // story first cost you the ability to keep it — which is a penalty for
    // using the feature, not a rule about freshness. What still has to hold is
    // that a qualifying walk or run happened today.
    //
    // Caption edits stay ungated. Fixing a typo isn't posting a photo, and a
    // post that's already on the feed shouldn't freeze at whatever text it
    // shipped with.
    if (
      addToFeed &&
      (await userSupports(userId, CLIENT_FEATURES.postWindowV1))
    ) {
      const goal = await getDailyGoalStatus(userId);
      const postWindow = goal.completed
        ? await getPostWindowStatus(userId, goal.localDate)
        : null;
      if (!postWindow?.photoOpen) {
        return res.status(403).json({
          error: "post_window_closed",
          reason: "no_workout_today",
          photo_open: false,
          window_seconds: Math.round(POST_WINDOW_MS / 1000),
        });
      }
    }

    const result = await updateOwnPost(userId, postId, {
      ...(hasCaption
        ? {
            caption:
              typeof caption === "string" ? caption.trim() || null : null,
          }
        : {}),
      ...(addToFeed ? { addToFeed: true } : {}),
    });
    if (result === "not_found") {
      return res.status(404).json({ error: "Post not found" });
    }
    if (result === "feed_conflict") {
      return res.status(409).json({ error: "workout_already_posted" });
    }
    res.json({ ok: true });
  } catch (error: any) {
    console.error("Error updating post:", error.message);
    res.status(500).json({ error: "Error updating post" });
  }
}

/**
 * PUT /posts/:postId/crew-photo — a credited participant's own photo on a
 * shared buddy post.
 *
 * The door that stops a buddy walk becoming N posts. Everyone on the walk
 * wants to share their picture of it; before this, the only way to do that was
 * to open a second post for the same walk, so a walk two people took filled
 * the feed twice with the crew split across both cards. Here it becomes
 * another slide on the card that already exists.
 *
 * Gated exactly like creating a post, deliberately: the media-ownership check,
 * the on-disk check, and the day/camera tiers. A photo reaching the feed
 * through a side door must not buy a looser rule than the front one.
 */
export async function addCrewPhotoController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const userId = req.userId!;
  const postId = req.params.postId;
  const { media_url, photo_source } = req.body ?? {};
  try {
    if (!isUuid(postId)) {
      return res.status(404).json({ error: "Post not found" });
    }
    // Same three media checks createPost runs, in the same order. The
    // ownership one is not optional: media urls are visible to the whole
    // circle, so without it anyone credited on a post could pin a friend's
    // photo to it as their own.
    const mediaUrl =
      typeof media_url === "string" ? stripMediaQuery(media_url) : media_url;
    if (
      typeof mediaUrl !== "string" ||
      !mediaUrl.startsWith(POSTS_MEDIA_PREFIX) ||
      mediaUrl.includes("..")
    ) {
      return res
        .status(400)
        .json({ error: "A valid uploaded media_url is required" });
    }
    if (!fs.existsSync(path.join(process.cwd(), mediaUrl.replace(/^\//, "")))) {
      return res
        .status(400)
        .json({ error: "media_url does not reference an uploaded file" });
    }
    if (!path.basename(mediaUrl).startsWith(`${userId}-`)) {
      return res
        .status(403)
        .json({ error: "media_url must reference your own upload" });
    }

    // Adding your slide is posting a photo, so it answers to the same window.
    // Which tier applies is the client's declared source, same split as
    // createPost: a live capture is on the ten-minute clock, a camera-roll
    // pick is bounded by when it was SHOT and only needs a qualifying walk
    // today.
    if (await userSupports(userId, CLIENT_FEATURES.postWindowV1)) {
      const goal = await getDailyGoalStatus(userId);
      const postWindow = goal.completed
        ? await getPostWindowStatus(userId, goal.localDate)
        : null;
      const needsCamera = photoSourceRequiresCameraWindow(photo_source);
      const allowed = needsCamera
        ? postWindow?.cameraOpen
        : postWindow?.photoOpen;
      if (!allowed) {
        return res.status(403).json({
          error: "post_window_closed",
          reason: needsCamera ? "camera_window_closed" : "no_workout_today",
          photo_open: postWindow?.photoOpen === true,
          window_seconds: Math.round(POST_WINDOW_MS / 1000),
        });
      }
    }

    // Membership IS the authorization — you may add a photo to a post you are
    // accepted on and to nothing else. A miss is 404 rather than 403 so the
    // existence of someone else's post is never confirmed.
    const ok = await addCrewPhoto(postId, userId, mediaUrl);
    if (!ok) return res.status(404).json({ error: "Post not found" });
    // Fire-and-forget: everyone else on the walk hears about it, and a push
    // that fails must never fail the photo that already landed.
    void notifyCrewPhoto(postId, userId);
    res.json({ ok: true });
  } catch (error: any) {
    console.error("Error adding crew photo:", error.message);
    res.status(500).json({ error: "Error adding crew photo" });
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
    if (!isUuid(postId)) {
      return res.status(404).json({ error: "Post not found" });
    }
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

/**
 * POST /posts/:postId/coauthor — { accept: boolean }. The invited coauthor
 * accepts (pending → accepted, links their mile) or declines/leaves (clears
 * the collab, works from pending OR accepted).
 */
export async function respondToCoauthorController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!isUuid(req.params.postId)) {
      return res.status(404).json({ error: "post_not_found" });
    }
    if (typeof req.body?.accept !== "boolean") {
      return res.status(400).json({ error: "accept must be a boolean" });
    }
    // Legacy scalar path first — it also updates the mirrored post_coauthors
    // row, so a responder who is BOTH the mirror and a multi-collab member is
    // fully resolved by this one call.
    const result = await respondToCoauthorInvite(
      req.userId!,
      req.params.postId,
      req.body.accept,
    );

    if (result) {
      // Keep the multi-collab row in step for the mirrored participant.
      await respondToMultiCoauthorInvite(
        req.userId!,
        req.params.postId,
        req.body.accept,
      );
      if (req.body.accept) {
        notifyCoauthorAccepted(
          req.userId!,
          result.author_id,
          req.params.postId,
        ).catch(() => {});
      }
      return res.json({ ok: true });
    }

    // Not the mirrored coauthor — they may still be one of the other credited
    // participants on a multi-person collab.
    const respondedMulti = await respondToMultiCoauthorInvite(
      req.userId!,
      req.params.postId,
      req.body.accept,
    );
    if (!respondedMulti) {
      return res.status(404).json({ error: "invite_not_found" });
    }
    if (req.body.accept) {
      const authorRows = await postAuthorId(req.params.postId);
      if (authorRows) {
        notifyCoauthorAccepted(
          req.userId!,
          authorRows,
          req.params.postId,
        ).catch(() => {});
      }
    }
    res.json({ ok: true });
  } catch (error: any) {
    console.error("Error responding to coauthor invite:", error.message);
    res.status(500).json({ error: "Error responding to coauthor invite" });
  }
}

/**
 * POST /posts/:postId/coauthor/profile — { on_profile: boolean }. The tagged
 * coauthor pins this collab on or off their own profile grid. The tag itself
 * is untouched: it stays in their Tagged tab and on every feed it already
 * reached. Separate route rather than an extra field on /coauthor so the
 * destructive "remove me" and this reversible one can never be confused.
 */
export async function setCoauthorProfileVisibilityController(
  req: AuthenticatedRequest,
  res: Response,
) {
  try {
    if (!isUuid(req.params.postId)) {
      return res.status(404).json({ error: "post_not_found" });
    }
    if (typeof req.body?.on_profile !== "boolean") {
      return res.status(400).json({ error: "on_profile must be a boolean" });
    }
    const result = await setCoauthorProfileVisibility(
      req.userId!,
      req.params.postId,
      req.body.on_profile,
    );
    if (!result) {
      return res.status(404).json({ error: "collab_not_found" });
    }
    res.json({ ok: true, on_profile: req.body.on_profile });
  } catch (error: any) {
    console.error("Error setting collab profile visibility:", error.message);
    res.status(500).json({ error: "Error setting collab profile visibility" });
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

/**
 * GET /posts/window — can a photo be posted right now, and for how much longer?
 *
 * The client runs its own countdown off the workout it saw finish, which is
 * what drives the compose UI. This is the reconciling read for the cases that
 * countdown can't cover: a second device that never observed the workout, a
 * cold launch after a Watch run synced in the background, or simply a client
 * that wants to check before opening the composer rather than after.
 *
 * Reports the DISPLAY window (`seconds_remaining` hits 0 at the ten-minute
 * mark); the create path's grace is deliberately not published, so a client
 * counting down to zero is never the reason a post is refused.
 *
 * `open` is the CAMERA tier and keeps its original meaning, because that is
 * what shipped builds read it as. `camera_open` is the same value under the
 * name the split gave it, and `photo_open` is the day tier — a camera-roll
 * pick or a story promotion is allowed whenever that one is true.
 */
export async function getPostWindowController(
  req: AuthenticatedRequest,
  res: Response,
) {
  const userId = req.userId!;
  try {
    const goal = await getDailyGoalStatus(userId);
    // No goal, no window — report it as closed rather than surfacing a window
    // that the mile gate would reject anyway.
    const postWindow = goal.completed
      ? await getPostWindowStatus(userId, goal.localDate)
      : null;
    res.status(200).json({
      open: postWindow?.cameraOpen ?? false,
      camera_open: postWindow?.cameraOpen ?? false,
      photo_open: postWindow?.photoOpen ?? false,
      workout_id: postWindow?.workoutId ?? null,
      opened_at: postWindow?.openedAt ?? null,
      closes_at: postWindow?.closesAt ?? null,
      seconds_remaining: postWindow?.secondsRemaining ?? 0,
      window_seconds: Math.round(POST_WINDOW_MS / 1000),
      mile_completed: goal.completed,
    });
  } catch (error: any) {
    console.error("Error fetching post window:", error.message);
    res.status(500).json({ error: "Error fetching post window" });
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
