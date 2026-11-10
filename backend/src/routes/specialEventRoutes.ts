import { Router } from "express";
import { getSpecialEvents } from "../controllers/specialEventController.js";
import { requireSelfAccess } from "../middleware/auth.js";

// Mounted under /users alongside communityGoalRoutes.
const router = Router();

router.get("/:userId/special-events", requireSelfAccess("userId"), getSpecialEvents);

export default router;
