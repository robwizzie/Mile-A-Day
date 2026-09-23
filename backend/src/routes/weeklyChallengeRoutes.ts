import { Router } from "express";
import {
  getWeeklyChallenge,
  getWeeklyChallengeHistory,
} from "../controllers/weeklyChallengeController.js";
import { getWeeklyRecap } from "../controllers/weeklyRecapController.js";
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
// Same Sunday→Saturday week as the challenge, which is why it lives here.
router.get(
  "/:userId/weekly-recap",
  requireSelfAccess("userId"),
  getWeeklyRecap,
);

export default router;
