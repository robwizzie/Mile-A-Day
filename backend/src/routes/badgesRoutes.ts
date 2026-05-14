import { Router } from "express";
import {
  getPublicCatalog,
  getBadgesForUser,
  markViewed,
  setPinnedBadgesForUser,
} from "../controllers/badgeController.js";
import { requireSelfAccess } from "../middleware/auth.js";

// Public router — only mount before authenticateToken.
export const publicBadgesRouter = Router();
publicBadgesRouter.get("/catalog", getPublicCatalog);

// Authenticated router — mount after authenticateToken.
const router = Router();
router.get("/:userId/badges", getBadgesForUser);
router.post(
  "/:userId/badges/mark-viewed",
  requireSelfAccess("userId"),
  markViewed,
);
router.put(
  "/:userId/badges/pins",
  requireSelfAccess("userId"),
  setPinnedBadgesForUser,
);

export default router;
