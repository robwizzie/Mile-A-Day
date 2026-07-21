import { Router } from "express";
import multer from "multer";
import {
  deleteUser,
  getUser,
  searchUsers,
  updateUser,
  updateUserUsername,
  checkUsername,
  updateUserBio,
  updateUserProfileImage,
  updateUserOnboarding,
  uploadProfileImage,
} from "../controllers/usersController.js";
import { requireSelfAccess } from "../middleware/auth.js";
import {
  enableStreakFeaturesController,
  streakFeaturesStatusController,
  giveStreakAssistController,
} from "../controllers/streakFeaturesController.js";

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
  fileFilter: (_req, file, cb) => {
    if (["image/jpeg", "image/png", "image/webp"].includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error("Only JPEG, PNG, and WebP images are allowed"));
    }
  },
});

const router = Router();

// Streak tokens (Double Down / Streak Save / Streak Assist). Self-scoped via
// req.userId, so no :userId param — registered above the param routes so the
// static paths can never be captured by /:userId.
router.post("/streak-features/enable", enableStreakFeaturesController);
router.get("/streak-features/status", streakFeaturesStatusController);
router.post("/streak-features/assist/:friendId", giveStreakAssistController);

router.get("/search", searchUsers);
router.get("/check-username", checkUsername);
router.get("/:userId", getUser);
router.delete("/:userId", requireSelfAccess("userId"), deleteUser);
router.patch("/:userId", requireSelfAccess("userId"), updateUser);
router.patch(
  "/:userId/username",
  requireSelfAccess("userId"),
  updateUserUsername,
);
router.patch("/:userId/bio", requireSelfAccess("userId"), updateUserBio);
router.patch(
  "/:userId/onboarding",
  requireSelfAccess("userId"),
  updateUserOnboarding,
);
router.patch(
  "/:userId/profile-image",
  requireSelfAccess("userId"),
  updateUserProfileImage,
);
router.post(
  "/:userId/profile-image/upload",
  requireSelfAccess("userId"),
  upload.single("image"),
  uploadProfileImage,
);

export default router;
