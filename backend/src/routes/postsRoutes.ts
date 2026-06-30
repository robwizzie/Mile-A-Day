import { Router } from "express";
import multer from "multer";
import {
  uploadPostMedia,
  createPostController,
  getStoriesRailController,
  getUserStoriesController,
  markStoryViewedController,
  getFeedController,
  getUnifiedFeedController,
  getUserPostsController,
  deletePostController,
  reportPostController,
  getTermsStatusController,
  acceptTermsController,
} from "../controllers/postsController.js";

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

// Media upload, then JSON create referencing the returned media_url.
router.post("/media", upload.single("image"), uploadPostMedia);
router.post("/", createPostController);

// Stories.
router.get("/stories", getStoriesRailController);
router.get("/stories/:userId", getUserStoriesController);
router.post("/stories/:postId/view", markStoryViewedController);

// Persistent feed (photo-only) + unified feed (posts + workout activity).
router.get("/feed", getFeedController);
router.get("/feed/unified", getUnifiedFeedController);

// A user's posts for the Instagram-style profile grid.
router.get("/user/:userId", getUserPostsController);

// Per-post actions.
router.post("/:postId/report", reportPostController);
router.delete("/:postId", deletePostController);

export default router;
