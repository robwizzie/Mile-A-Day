import { Router } from "express";
import { getCommunityGoal } from "../controllers/communityGoalController.js";
import { requireSelfAccess } from "../middleware/auth.js";

// Mounted under /users alongside weeklyChallengeRoutes.
const router = Router();

router.get("/:userId/community-goal", requireSelfAccess("userId"), getCommunityGoal);

export default router;
