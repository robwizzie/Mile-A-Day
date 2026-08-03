import { Router } from "express";
import {
  startLiveTracking,
  liveTrackingHeartbeat,
  endLiveTracking,
} from "../controllers/liveTrackingController.js";

const router = Router();

// All self-scoped on req.userId (mounted after authenticateToken in
// server.ts). Presence is pull-only: the tracker starts a session, beats
// every ~45s (the response carries friends-out + hypes-since-start), and
// ends it on stop. See liveTrackingService for the presence window.
router.post("/start", startLiveTracking);
router.post("/heartbeat", liveTrackingHeartbeat);
router.post("/end", endLiveTracking);

export default router;
