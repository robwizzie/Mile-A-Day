import { Router } from "express";
import { getReferrals, postClaimFreeYear, postReferrer } from "../controllers/referralController.js";
import { requireSelfAccess } from "../middleware/auth.js";

// Mounted under /users.
const router = Router();

router.get("/:userId/referrals", requireSelfAccess("userId"), getReferrals);
router.post("/:userId/referrals/referrer", requireSelfAccess("userId"), postReferrer);
router.post("/:userId/referrals/free-year", requireSelfAccess("userId"), postClaimFreeYear);

export default router;
