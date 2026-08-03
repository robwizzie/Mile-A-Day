import { Router } from "express";
import {
  startLiveTracking,
  liveTrackingHeartbeat,
  endLiveTracking,
  liveFriendsOut,
} from "../controllers/liveTrackingController.js";

const router = Router();

// All self-scoped on req.userId (mounted after authenticateToken in
// server.ts). Presence is pull-only: the tracker starts a session, beats
// every ~45s (the response carries friends-out + hypes-since-start), and
// ends it on stop. See liveTrackingService for the presence window.
router.post("/start", startLiveTracking);
router.post("/heartbeat", liveTrackingHeartbeat);
router.post("/end", endLiveTracking);
// Dashboard-callable: who's out right now, WITHOUT an active session of your
// own. The heartbeat only answers this once you're already walking.
router.get("/friends-out", liveFriendsOut);

export default router;
