import { Router } from "express";
import {
  appleNotificationController,
  listGiftsController,
  plusStatusController,
  postTransactionsController,
  redeemGiftController,
} from "../controllers/plusController.js";
import { plusRedeemLimiter } from "../middleware/rateLimit.js";

// Mounted at /plus AFTER authenticateToken in server.ts. Every route is
// self-scoped on req.userId — there is no :userId param to check.
const router = Router();

router.get("/status", plusStatusController);
router.post("/transactions", postTransactionsController);
router.get("/gifts", listGiftsController);
router.post("/gifts/redeem", plusRedeemLimiter, redeemGiftController);

export default router;

// Mounted at /store BEFORE authenticateToken: Apple's App Store Server
// Notifications V2 webhook. It authenticates by Apple's JWS signature, which
// the controller verifies before reading anything.
export const storePublicRouter = Router();
storePublicRouter.post("/apple/notifications", appleNotificationController);
