import { Router } from "express";
import {
  endInjuryPauseController,
  injuryPauseStatusController,
  startInjuryPauseController,
} from "../controllers/injuryPauseController.js";

const router = Router();

// Mounted at /streak AFTER authenticateToken in server.ts. Everything here
// authorizes off req.userId — there is no :userId path param, so
// requireSelfAccess has nothing to check.

// GET returns the same status shape the two writes return, so a client can
// re-render from any of the three without a follow-up read.
router.get("/pause", injuryPauseStatusController);
// Optional body { started_on: "YYYY-MM-DD" } backdates the pause; the format
// is checked in the controller, how far back it may reach in the service.
router.post("/pause", startInjuryPauseController);
router.delete("/pause", endInjuryPauseController);

export default router;
