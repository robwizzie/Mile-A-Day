import { Router } from "express";
import {
  adjustController,
  applyController,
  archiveController,
  checkinController,
  createController,
  currentController,
  declineController,
  fitnessController,
  proposalController,
  requirePlus,
  revokeClaudeController,
  updateController,
} from "../controllers/runPlansController.js";

// Mounted at /run-plans AFTER authenticateToken in server.ts. Self-scoped on
// req.userId. Mile A Day+ only: everything below the gate answers 403
// `{ error: 'plus_required' }` to everyone else — except revoking Claude's
// access, which a lapsed subscriber must still be able to do.
const router = Router();

router.delete("/claude", revokeClaudeController);

router.use(requirePlus);
router.get("/fitness", fitnessController);
router.get("/current", currentController);
router.post("/", createController);
router.patch("/current", updateController);
router.delete("/current", archiveController);
router.post("/checkins", checkinController);
router.post("/proposals", proposalController);
router.post("/proposals/:id/apply", applyController);
router.post("/proposals/:id/decline", declineController);
router.post("/days/:date/adjust", adjustController);

export default router;
