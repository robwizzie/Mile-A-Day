import { Router } from "express";
import multer from "multer";
import {
  uploadPostMedia,
  createPostController,
  getStoriesRailController,
  getUserStoriesController,
  markStoryViewedController,
  getStoryViewersController,
  getStoryReactorsController,
  reactToStoryController,
  getPostMemoriesController,
  getFeedController,
  getUnifiedFeedController,
  getUserPostsController,
  getPostController,
  getUserTaggedPostsController,
  deletePostController,
  updatePostController,
  reportPostController,
  addCrewPhotoController,
  getTermsStatusController,
  acceptTermsController,
  getPostWindowController,
  respondToCoauthorController,
  setCoauthorProfileVisibilityController,
  setCoauthorFeedVisibilityController,
  setCoauthorRouteController,
  setPostPinnedController,
  listHighlightsController,
  getHighlightController,
  createHighlightController,
  updateHighlightController,
  deleteHighlightController,
} from "../controllers/postsController.js";
import {
  listCommentsController,
  listWorkoutCommentsController,
  addCommentController,
  addWorkoutCommentController,
  deleteCommentController,
  reportCommentController,
} from "../controllers/commentsController.js";

// Post photos are larger than avatars (full-res portrait stories), so allow 8MB.
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 8 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (["image/jpeg", "image/png", "image/webp"].includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error("Only JPEG, PNG, and WebP images are allowed"));
    }
  },
});

const router = Router();

// Terms / EULA gate (App Store Guideline 1.2).
router.get("/terms", getTermsStatusController);
router.post("/terms/accept", acceptTermsController);

// How long the caller may still post a photo for (see getPostWindowController).
// Above the `/:postId` routes so "window" isn't parsed as a post id.
router.get("/window", getPostWindowController);

// Media upload, then JSON create referencing the returned media_url.
router.post("/media", upload.single("image"), uploadPostMedia);
router.post("/", createPostController);

// Stories.
router.get("/stories", getStoriesRailController);
router.get("/stories/:userId", getUserStoriesController);
router.post("/stories/:postId/view", markStoryViewedController);
router.get("/stories/:postId/viewers", getStoryViewersController);
router.get("/stories/:postId/reactions", getStoryReactorsController);
router.post("/stories/:postId/react", reactToStoryController);

// "On this day" — the caller's own past post photos.
router.get("/memories", getPostMemoriesController);

// Story Highlights — named, permanent collections of your own posts, shown as
// a rail above the profile grid. Registered above the /:postId block for the
// usual reason: "highlights" would otherwise be parsed as a post id. The
// /detail/ segment keeps a highlight id from colliding with a user id on
// /highlights/:userId, which is the read every profile does.
router.get("/highlights/detail/:highlightId", getHighlightController);
router.get("/highlights/:userId", listHighlightsController);
router.post("/highlights", createHighlightController);
router.patch("/highlights/:highlightId", updateHighlightController);
router.delete("/highlights/:highlightId", deleteHighlightController);

// Persistent feed (photo-only) + unified feed (posts + workout activity).
router.get("/feed", getFeedController);
router.get("/feed/unified", getUnifiedFeedController);

// A user's posts for the Instagram-style profile grid, and the posts they're
// tagged in (accepted collabs + caption @mentions) for the "Tagged" tab.
router.get("/user/:userId/tagged", getUserTaggedPostsController);
router.get("/user/:userId", getUserPostsController);

// Comments (Instagram-style, one level of replies).
router.get("/workouts/:workoutId/comments", listWorkoutCommentsController);
router.post("/workouts/:workoutId/comments", addWorkoutCommentController);
router.get("/:postId/comments", listCommentsController);
router.post("/:postId/comments", addCommentController);
router.delete("/comments/:commentId", deleteCommentController);
router.post("/comments/:commentId/report", reportCommentController);

// Per-post actions. The bare GET is LAST among the /:postId routes on purpose
// — it's the most permissive pattern and would otherwise swallow /terms,
// /stories, /memories, /feed and /user (all registered above).
// More specific than /:postId/coauthor, so it must be registered first.
router.post(
  "/:postId/coauthor/profile",
  setCoauthorProfileVisibilityController,
);
// The coauthor's other two switches on a shared post: reach (does it go to MY
// friends' feeds) and route (is MY trace drawn on it). Separate from /profile
// because they are separate consents — see the controllers.
router.post("/:postId/coauthor/feed", setCoauthorFeedVisibilityController);
router.post("/:postId/coauthor/route", setCoauthorRouteController);
router.post("/:postId/coauthor", respondToCoauthorController);
// Pin/unpin one of your own posts to the top of your grid (author only).
router.post("/:postId/pin", setPostPinnedController);
router.post("/:postId/report", reportPostController);
// A buddy walk is one walk, so it gets one post — and everyone on it puts
// their own photo on THAT post here, rather than opening a second card for the
// same hour. PUT because re-sending replaces your slide; it is not a second
// one.
router.put("/:postId/crew-photo", addCrewPhotoController);
router.patch("/:postId", updatePostController);
router.delete("/:postId", deletePostController);
// One post, shaped like its feed entry — opening a post directly.
router.get("/:postId", getPostController);

export default router;
