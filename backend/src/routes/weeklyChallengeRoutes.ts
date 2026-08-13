import { Router } from "express";
import {
  getWeeklyChallenge,
  getWeeklyChallengeHistory,
} from "../controllers/weeklyChallengeController.js";
import { requireSelfAccess } from "../middleware/auth.js";

// Mounted under /users alongside dailyChallengesRoutes. No collision with
// /users/:userId/challenges/* — the segment differs.
const router = Router();

router.get(
  "/:userId/weekly-challenge/history",
  requireSelfAccess("userId"),
  getWeeklyChallengeHistory,
);
router.get(
  "/:userId/weekly-challenge",
  requireSelfAccess("userId"),
  getWeeklyChallenge,
);

export default router;
